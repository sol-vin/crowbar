require "option_parser"
require "opal"
require "../../crowbar"
require "./diff"
require "./platform_io"
require "./catalog_view"
require "./session_handler"

module Crowbar::CLI
  class ExitException < Exception
    getter code : Int32

    def initialize(@code : Int32)
      super("Process exited with code #{@code}")
    end
  end

  # Main CLI application runner and orchestrator
  class App
    property in_io : IO
    property out_io : IO
    property err_io : IO
    property exit_handler : Proc(Int32, Nil)

    def self.run(args : Array(String) = ARGV)
      new.run(args)
    end

    @count : Int32 = 1
    @seed : UInt64? = nil
    @output_pattern : String? = nil
    @selected_mutations : String? = nil
    @selected_pattern : String? = nil
    @selected_rule : String? = nil
    @show_diff : Bool = false
    @auto_detect : Bool = false
    @json_output : Bool = false
    @input_files : Array(String) = [] of String

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

    private def print(msg = "")
      @out_io.print(msg)
    end

    private def err_puts(msg = "")
      @err_io.puts(msg)
    end

    private def do_exit(code : Int32 = 0)
      @exit_handler.call(code)
    end

    def run(args : Array(String))
      @json_output = args.includes?("--json")
      @auto_detect = args.includes?("--auto")
      @show_diff = args.includes?("--diff") || args.includes?("-d")

      # Handle session subcommands if present
      if args.includes?("session")
        remaining = extract_flags(args)
        handler = SessionHandler.new(
          in_io: @in_io,
          out_io: @out_io,
          err_io: @err_io,
          exit_handler: @exit_handler,
          selected_rule: @selected_rule,
          selected_pattern: @selected_pattern,
          selected_mutations: @selected_mutations,
          seed: @seed,
          show_diff: @show_diff,
          output_pattern: @output_pattern,
          json_output: @json_output,
        )
        session_idx = remaining.index("session").not_nil!
        sub_args = remaining[(session_idx + 1)..]
        handler.handle(sub_args)
        return
      end

      parser = OptionParser.new do |opts|
        opts.banner = Opal.style.bold.fg(:cyan).render("Crowbar #{Crowbar.version} - Data Transformation & Fuzzing Engine") +
                      "\nUsage: crowbar [options] [sample-files...]" +
                      "\n       crowbar session <id> next" +
                      "\n       crowbar session <id> reward <value>" +
                      "\n       crowbar session <id> show [--baseline | --mutant]" +
                      "\n       crowbar session <id> history [--limit N]" +
                      "\n       crowbar session <id> reset"

        opts.on("-n COUNT", "--count COUNT", "Number of test cases to generate (default: 1, -1 for inf)") do |c|
          @count = c.to_i
        end

        opts.on("-s SEED", "--seed SEED", "Deterministic 64-bit random seed") do |s|
          @seed = s.to_u64? || s.hash.to_u64
        end

        opts.on("-o PATTERN", "--output PATTERN", "Output destination: '-' (stdout) or 'out-%n.ext'") do |o|
          @output_pattern = o
        end

        opts.on("-m LIST", "--mutations LIST", "Filter mutators (e.g. bd,bf,num)") do |m|
          @selected_mutations = m
        end

        opts.on("-p PATTERN", "--patterns PATTERN", "Execution pattern: once (od), many (nd), burst (bu)") do |p|
          @selected_pattern = p
        end

        opts.on("-r RULE", "--rule RULE", "Structure-preserving rule (e.g. json, http, mp3, wad, pdf)") do |r|
          @selected_rule = r
        end

        opts.on("-f FORMAT", "--format FORMAT", "Alias for --rule: format name or extension") do |f|
          @selected_rule = f
        end

        opts.on("--auto", "Auto-detect input format from magic bytes and attach matching rule") do
          @auto_detect = true
        end

        opts.on("-d", "--diff", "Display Opal TrueColor terminal hex diff") do
          @show_diff = true
        end

        opts.on("--json", "Emit machine-readable JSON output for listings and statuses") do
          @json_output = true
        end

        opts.on("-l", "--list", "List all available rules, mutators, patterns, and selectors") do
          CatalogView.render_catalog(@out_io, @json_output)
          do_exit(0)
        end

        opts.on("--list-rules", "List all structure-preserving format rules") do
          CatalogView.render_rules(@out_io, @json_output)
          do_exit(0)
        end

        opts.on("--list-mutators", "List all registered mutation operators") do
          CatalogView.render_mutators(@out_io, @json_output)
          do_exit(0)
        end

        opts.on("-v", "--version", "Print version") do
          puts "Crowbar #{Crowbar.version}"
          do_exit(0)
        end

        opts.on("-h", "--help", "Show help message") do
          puts opts
          do_exit(0)
        end
      end

      parser.parse(args)
      @input_files = args

      # Read input corpus
      input_buffer = read_input

      if input_buffer.empty?
        err_puts Opal.style.fg(:yellow).render("Warning: No input data provided. Supply a sample file or pipe data via STDIN.")
        do_exit(1)
        return
      end

      # Auto-detect rule if requested and not explicitly set
      if @auto_detect && @selected_rule.nil?
        if detected = Detector.detect(input_buffer)
          @selected_rule = detected.to_s
        end
      end

      # Construct engine
      engine = Crowbar::Engine.new(@seed || PRNG.default_seed)

      # Apply pattern if requested
      if pat = @selected_pattern
        if p_obj = Patterns.create?(pat)
          engine.pattern = p_obj
        end
      end

      # Apply rule if requested
      if rule_name = @selected_rule
        if r_obj = Rules::Registry.create?(rule_name)
          engine.add_rule(r_obj)
        else
          err_puts Opal.style.fg(:red).render("Error: Unknown rule or format '#{rule_name}'")
          do_exit(1)
          return
        end
      end

      # Filter mutators if requested
      if mut_list = @selected_mutations
        names = mut_list.split(",").map(&.strip)
        engine.pool.mutators.clear
        pool = MutatorPool.new
        names.each do |n|
          if m = pool.find?(n)
            engine.pool.register(m)
          end
        end
      end

      # Execution loop
      iteration = 1
      loop do
        mutated = engine.transform(input_buffer)

        if @show_diff
          HexDiff.render(input_buffer, mutated, @out_io)
        elsif pattern = @output_pattern
          write_output(pattern, mutated, iteration)
        else
          # Default: emit mutated bytes to out_io
          @out_io.write(mutated.to_slice)
        end

        break if @count > 0 && iteration >= @count
        iteration += 1
      end
    end

    private def read_input : Buffer
      if !@input_files.empty?
        # Read from first sample file (or concatenate)
        file_path = @input_files.first
        if File.exists?(file_path)
          Buffer.new(File.read(file_path))
        else
          err_puts "Error: File '#{file_path}' does not exist"
          do_exit(1)
          Buffer.new
        end
      else
        # Read from input IO
        Buffer.from_io(@in_io)
      end
    end

    private def write_output(pattern : String, buffer : Buffer, iteration : Int32)
      if pattern == "-"
        @out_io.write(buffer.to_slice)
      else
        filename = pattern.gsub("%n", iteration.to_s)
        File.write(filename, buffer.to_slice)
      end
    end

    private def extract_flags(args : Array(String)) : Array(String)
      remaining = [] of String
      i = 0
      while i < args.size
        arg = args[i]
        case arg
        when "-r", "--rule", "-f", "--format"
          if i + 1 < args.size
            @selected_rule = args[i + 1]
            i += 2
            next
          end
        when "-s", "--seed"
          if i + 1 < args.size
            @seed = args[i + 1].to_u64? || args[i + 1].hash.to_u64
            i += 2
            next
          end
        when "-p", "--patterns", "--pattern"
          if i + 1 < args.size
            @selected_pattern = args[i + 1]
            i += 2
            next
          end
        when "-m", "--mutations"
          if i + 1 < args.size
            @selected_mutations = args[i + 1]
            i += 2
            next
          end
        when "-d", "--diff"
          @show_diff = true
          i += 1
          next
        when "--json"
          @json_output = true
          i += 1
          next
        when "--auto"
          @auto_detect = true
          i += 1
          next
        when "-o", "--output"
          if i + 1 < args.size
            @output_pattern = args[i + 1]
            i += 2
            next
          end
        else
          remaining << arg
          i += 1
        end
      end
      remaining
    end
  end
end
