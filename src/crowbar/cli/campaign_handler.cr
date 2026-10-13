require "opal"
require "file_utils"
require "../campaign/target"
require "../campaign/runner"
require "../campaign/battery"
require "../campaign/report"
require "../dsl/campaign_builder"

module Crowbar::CLI
  # Command handler for executing mutation fuzzing campaigns
  class CampaignHandler
    property in_io : IO
    property out_io : IO
    property err_io : IO
    property exit_handler : Proc(Int32, Nil)

    def initialize(
      @in_io : IO = STDIN,
      @out_io : IO = STDOUT,
      @err_io : IO = STDERR,
      @exit_handler : Proc(Int32, Nil) = ->(code : Int32) { exit(code) },
    )
    end

    private def puts(msg = "")
      @out_io.puts(msg)
    end

    private def err_puts(msg = "")
      @err_io.puts(msg)
    end

    private def do_exit(code : Int32 = 0)
      @exit_handler.call(code)
    end

    def handle(args : Array(String))
      iterations = 200
      target_filter : String? = nil
      max_duration_sec : Int32? = nil
      seed : UInt64 = 42_u64
      timeout_ms = 500
      output_dir = "artifacts/fuzz"
      markdown_file : String? = nil
      json_file : String? = nil
      auto_shrink = true
      summary_step = false
      quiet = false

      i = 0
      while i < args.size
        case args[i]
        when "-n", "--iterations", "--count"
          iterations = args[i + 1]?.try(&.to_i?) || 200
          i += 2
        when "-t", "--target"
          target_filter = args[i + 1]?
          i += 2
        when "-d", "--duration"
          max_duration_sec = args[i + 1]?.try(&.to_i?)
          i += 2
        when "-s", "--seed"
          seed = args[i + 1]?.try(&.to_u64?) || 42_u64
          i += 2
        when "--timeout"
          timeout_ms = args[i + 1]?.try(&.to_i?) || 500
          i += 2
        when "-o", "--output-dir"
          output_dir = args[i + 1]? || output_dir
          i += 2
        when "--markdown"
          markdown_file = args[i + 1]?
          i += 2
        when "--json"
          json_file = args[i + 1]?
          i += 2
        when "--no-shrink"
          auto_shrink = false
          i += 1
        when "--summary-step"
          summary_step = true
          i += 1
        when "--quiet", "-q"
          quiet = true
          i += 1
        when "-h", "--help"
          print_help
          do_exit(0)
          return
        else
          i += 1
        end
      end

      # Configure Campaign Runner
      runner = Campaign::Runner.new(
        name: "Nightly Crowbar Mutation Fuzzing",
        iterations_per_target: iterations,
        max_duration: max_duration_sec ? max_duration_sec.not_nil!.seconds : nil,
        seed: seed,
        auto_shrink: auto_shrink,
        watchdog_interval: 10.seconds
      )

      # Target selection
      if target_filter && target_filter != "all"
        target_names = target_filter.split(',').map(&.strip)
        target_names.each do |t_name|
          target = case t_name.downcase
                   when "json", "json_parser"      then Campaign::Battery.json_target
                   when "yaml", "yaml_parser"      then Campaign::Battery.yaml_target
                   when "jwt", "jwt_validator"     then Campaign::Battery.jwt_target
                   when "http", "http_request"     then Campaign::Battery.http_target
                   when "csv", "csv_parser"        then Campaign::Battery.csv_target
                   when "uri", "uri_parser"        then Campaign::Battery.uri_target
                   when "base64", "base64_decoder" then Campaign::Battery.base64_target
                   when "packet", "packet_framing" then Campaign::Battery.packet_target
                   else
                     err_puts Opal.style.fg(:red).render("Unknown target '#{t_name}'. Available: json, yaml, jwt, http, csv, uri, base64, packet, all")
                     do_exit(1)
                     return
                   end
          target.timeout = timeout_ms.milliseconds
          runner.add_target(target)
        end
      else
        Campaign::Battery.all_targets.each do |target|
          target.timeout = timeout_ms.milliseconds
          runner.add_target(target)
        end
      end

      banner = Opal.style.bold.fg(:cyan).render("=== Crowbar Nightly Mutation Fuzzing Campaign ===")
      puts banner unless quiet
      puts "Targets: #{runner.targets.map(&.name).join(", ")} | Iterations/Target: #{iterations} | Seed: #{seed}" unless quiet
      puts "" unless quiet

      # Progress & Watchdog reporting
      runner.on_heartbeat = ->(iters : Int32, elapsed : Float64) {
        ops = elapsed > 0 ? (iters / elapsed).round(1) : 0.0
        msg = sprintf("  [Watchdog Heartbeat] %d iterations completed, %.1fs elapsed (%.1f ops/s)", iters, elapsed, ops)
        puts Opal.style.fg(:dark_gray).render(msg) unless quiet
      }

      runner.on_crash = ->(crash : Campaign::CrashRecord) {
        msg = sprintf("  ⚠️  CRASH DETECTED on '%s' (iter #%d): %s: %s", crash.target_name, crash.iteration, crash.error_class, crash.error_message)
        err_puts Opal.style.bold.fg(:red).render(msg)
      }

      # Run Campaign
      report = runner.run

      # Output summary
      puts "" unless quiet
      puts Opal.style.bold.fg(:cyan).render("--- Campaign Results Summary ---") unless quiet
      printf(" Status:           %s\n", report.clean? ? Opal.style.bold.fg(:green).render("PASSED (Clean - Zero Crashes)") : Opal.style.bold.fg(:red).render("FAILED (#{report.total_crashes} crashes)")) unless quiet
      printf(" Total Iterations: %d\n", report.total_iterations) unless quiet
      printf(" Total Duration:   %.2fs\n", report.total_duration_seconds) unless quiet
      printf(" Overall Rate:     %.1f ops/sec\n", report.overall_throughput_ops_sec) unless quiet
      printf(" Unique Crashes:   %d\n", report.unique_crashes) unless quiet
      printf(" Timeouts:         %d\n", report.total_timeouts) unless quiet
      puts "" unless quiet

      # Target Table
      unless quiet
        puts " ────────────────────────────────────────────────────────────────────────────────────────"
        printf(" %-16s %-14s %8s %8s %8s %8s %12s\n", "TARGET", "CATEGORY", "ITERS", "PASS", "ERRORS", "CRASHES", "THROUGHPUT")
        puts " ────────────────────────────────────────────────────────────────────────────────────────"
        report.targets.each_value do |ts|
          printf(" %-16s %-14s %8d %8d %8d %8s %10.1f o/s\n",
            ts.target_name,
            ts.category,
            ts.iterations,
            ts.passes,
            ts.expected_errors,
            ts.crashes > 0 ? Opal.style.bold.fg(:red).render(ts.crashes.to_s) : Opal.style.fg(:green).render("0"),
            ts.throughput_ops_sec
          )
        end
        puts " ────────────────────────────────────────────────────────────────────────────────────────\n"
      end

      # Write artifacts
      FileUtils.mkdir_p(output_dir)

      # JSON report
      out_json_path = json_file || File.join(output_dir, "fuzz-report.json")
      File.write(out_json_path, report.to_json)
      puts "Saved JSON report: #{out_json_path}" unless quiet

      # Markdown report
      md_content = report.to_markdown
      out_md_path = markdown_file || File.join(output_dir, "fuzz-report.md")
      File.write(out_md_path, md_content)
      puts "Saved Markdown report: #{out_md_path}" unless quiet

      # Crash reproducers
      report.crashes.each_with_index do |crash, idx|
        crash_file = File.join(output_dir, "crash-#{crash.id}-#{crash.target_name}.bin")
        File.write(crash_file, crash.reproducer.to_slice)
        if min = crash.minimized_reproducer
          min_file = File.join(output_dir, "crash-#{crash.id}-min.bin")
          File.write(min_file, min.to_slice)
        end
      end

      # Step Summary integration
      step_summary_env = ENV["GITHUB_STEP_SUMMARY"]?
      if summary_step && step_summary_env && File.exists?(step_summary_env)
        File.open(step_summary_env, "a") do |f|
          f.puts md_content
        end
      end

      # Exit code determination
      if report.clean?
        do_exit(0)
      else
        do_exit(1)
      end
    end

    private def print_help
      puts "Usage: crowbar campaign [options]"
      puts ""
      puts "Runs an automated mutation fuzzing campaign across structured parsers and protocols."
      puts ""
      puts "Options:"
      puts "  -n, --iterations COUNT     Number of mutation iterations per target (default: 200)"
      puts "  -t, --target NAME          Filter target: json, yaml, jwt, http, csv, uri, base64, packet, all"
      puts "  -d, --duration SEC         Maximum campaign runtime in seconds"
      puts "  -s, --seed SEED            64-bit random seed (default: 42)"
      puts "      --timeout MS           Per-iteration execution timeout in ms (default: 500)"
      puts "  -o, --output-dir DIR       Directory to store reports and crash reproducers (default: artifacts/fuzz)"
      puts "      --markdown FILE        Path to write Markdown summary report"
      puts "      --json FILE            Path to write JSON summary report"
      puts "      --no-shrink            Disable automatic delta minimization for crashes"
      puts "      --summary-step         Append report to $GITHUB_STEP_SUMMARY in CI"
      puts "  -q, --quiet                Suppress non-essential stdout output"
      puts "  -h, --help                 Show this help message"
    end
  end
end
