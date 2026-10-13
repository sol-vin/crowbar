require "json"
require "./target"
require "./result"

module Crowbar::Campaign
  # Performance and anomaly summary for an individual fuzz target
  struct TargetSummary
    include JSON::Serializable

    property target_name : String
    property category : String
    property iterations : Int32
    property passes : Int32
    property expected_errors : Int32
    property crashes : Int32
    property timeouts : Int32
    property anomalies : Int32
    property total_time_ms : Float64
    property average_entropy : Float64
    property throughput_ops_sec : Float64

    def initialize(
      @target_name : String,
      @category : String,
      @iterations : Int32 = 0,
      @passes : Int32 = 0,
      @expected_errors : Int32 = 0,
      @crashes : Int32 = 0,
      @timeouts : Int32 = 0,
      @anomalies : Int32 = 0,
      @total_time_ms : Float64 = 0.0,
      @average_entropy : Float64 = 0.0,
      @throughput_ops_sec : Float64 = 0.0,
    )
    end
  end

  # Comprehensive fuzzing campaign audit report
  class CampaignReport
    include JSON::Serializable

    property campaign_name : String
    property started_at : Time
    property completed_at : Time
    property total_iterations : Int32
    property total_crashes : Int32
    property unique_crashes : Int32
    property total_timeouts : Int32
    property total_duration_seconds : Float64
    property overall_throughput_ops_sec : Float64
    property targets : Hash(String, TargetSummary)
    property crashes : Array(CrashRecord)

    def initialize(
      @campaign_name : String,
      @started_at : Time,
      @completed_at : Time,
      @total_iterations : Int32 = 0,
      @total_crashes : Int32 = 0,
      @unique_crashes : Int32 = 0,
      @total_timeouts : Int32 = 0,
      @total_duration_seconds : Float64 = 0.0,
      @overall_throughput_ops_sec : Float64 = 0.0,
      @targets : Hash(String, TargetSummary) = Hash(String, TargetSummary).new,
      @crashes : Array(CrashRecord) = [] of CrashRecord,
    )
    end

    def clean? : Bool
      @total_crashes == 0 && @total_timeouts == 0
    end

    # Renders an executive GitHub-flavored Markdown report
    def to_markdown : String
      String.build do |str|
        status_badge = clean? ? "PASSED (Clean)" : "FAILED (#{@total_crashes} crashes, #{@total_timeouts} timeouts)"
        status_emoji = clean? ? "✅" : "❌"

        str.puts "# #{status_emoji} Crowbar Mutation Fuzzing Report: #{@campaign_name}"
        str.puts ""
        str.puts "- **Status**: `#{status_badge}`"
        str.puts "- **Started At**: `#{@started_at.to_utc.to_s("%Y-%m-%d %H:%M:%S UTC")}`"
        str.puts "- **Completed At**: `#{@completed_at.to_utc.to_s("%Y-%m-%d %H:%M:%S UTC")}`"
        str.puts "- **Duration**: `#{@total_duration_seconds.round(2)}s`"
        str.puts "- **Total Iterations**: `#{@total_iterations}`"
        str.puts "- **Overall Throughput**: `#{@overall_throughput_ops_sec.round(1)} ops/sec`"
        str.puts "- **Unique Crashes**: `#{@unique_crashes}`"
        str.puts "- **Timeouts**: #{@total_timeouts}"
        str.puts ""

        str.puts "## Target Execution Breakdown"
        str.puts ""
        str.puts "| Target | Category | Iterations | Passes | Handled Errors | Crashes | Timeouts | Avg Entropy | Throughput |"
        str.puts "| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |"

        @targets.each_value do |ts|
          str.printf("| **%s** | `%s` | %d | %d | %d | %s | %s | %.2f | %.1f ops/s |\n",
            ts.target_name,
            ts.category,
            ts.iterations,
            ts.passes,
            ts.expected_errors,
            ts.crashes > 0 ? "**#{ts.crashes}**" : "0",
            ts.timeouts > 0 ? "**#{ts.timeouts}**" : "0",
            ts.average_entropy,
            ts.throughput_ops_sec
          )
        end
        str.puts ""

        if @crashes.empty?
          str.puts "### Security & Resilience Verdict"
          str.puts "> [!NOTE]"
          str.puts "> Zero memory corruptions, infinite loops, or unhandled exceptions occurred across all #{@total_iterations} mutated payloads."
          str.puts "> Parsers successfully exercised and validated under structure-preserving mutation rules."
        else
          str.puts "## ⚠️ Crash & Anomaly Reproducers"
          @crashes.each_with_index do |crash, idx|
            str.puts "### Crash ##{idx + 1}: `#{crash.id}` on `#{crash.target_name}` (Iteration ##{crash.iteration})"
            str.puts "- **Error Type**: `#{crash.error_class}`"
            str.puts "- **Message**: `#{crash.error_message}`"
            str.puts "- **Original Size**: `#{crash.reproducer_size} bytes` (Entropy: `#{crash.reproducer_entropy.round(2)}`)"
            if min_sz = crash.minimized_size
              diff_pct = ((crash.reproducer_size - min_sz).to_f64 / crash.reproducer_size * 100.0).round(1)
              str.puts "- **Minimized Size**: `#{min_sz} bytes` (-#{diff_pct}% reduction)"
            end
            str.puts ""
            str.puts "```text"
            str.puts crash.backtrace.first(10).join("\n")
            str.puts "```"
            str.puts ""
            str.puts "<details><summary>Base64 Reproducer Payload</summary>"
            str.puts ""
            str.puts "```base64"
            str.puts crash.minimized_base64 || crash.reproducer_base64
            str.puts "```"
            str.puts "</details>"
            str.puts ""
          end
        end
      end
    end
  end
end
