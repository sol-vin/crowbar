require "../engine"
require "../inspector/analyzer"
require "../minimizer/reducer"
require "./target"
require "./result"
require "./report"

module Crowbar::Campaign
  # Multi-target mutation fuzzing campaign orchestrator enforcing 60-second
  # watchdog invariants, bounded execution timeouts, and automatic test case reduction.
  class Runner
    property name : String
    property targets : Array(Target)
    property iterations_per_target : Int32
    property max_duration : Time::Span?
    property seed : UInt64
    property auto_shrink : Bool
    property watchdog_interval : Time::Span

    # Callback signatures
    property on_progress : Proc(String, Int32, Int32, IterationResult, Nil)?
    property on_heartbeat : Proc(Int32, Float64, Nil)?
    property on_crash : Proc(CrashRecord, Nil)?

    def initialize(
      @name : String = "Nightly Mutation Fuzzing",
      @targets : Array(Target) = [] of Target,
      @iterations_per_target : Int32 = 200,
      @max_duration : Time::Span? = nil,
      @seed : UInt64 = 42_u64,
      @auto_shrink : Bool = true,
      @watchdog_interval : Time::Span = 10.seconds,
    )
    end

    def add_target(target : Target) : Nil
      @targets << target
    end

    # Executes the full fuzzing campaign across all targets
    def run : CampaignReport
      started_at = Time.utc
      last_watchdog = started_at
      total_iters = 0
      total_crashes = 0
      total_timeouts = 0
      crash_records = [] of CrashRecord
      seen_crash_ids = Set(String).new
      target_summaries = Hash(String, TargetSummary).new

      engine = Engine.new(@seed)

      @targets.each do |target|
        break if expired?(started_at)

        target_passes = 0
        target_expected_errors = 0
        target_crashes = 0
        target_timeouts = 0
        target_anomalies = 0
        target_entropy_sum = 0.0
        target_start = Time.utc

        # Prepare target mutation engine
        target_engine = Engine.new(@seed + total_iters.to_u64)
        target.rules.each { |r| target_engine.add_rule(r) }
        target_engine.pattern = target.pattern

        @iterations_per_target.times do |iter_idx|
          break if expired?(started_at)

          # Pick sample from corpus (or fallback to dummy baseline)
          sample = if target.samples.empty?
                     Buffer.new("default_seed_sample_#{target.name}")
                   else
                     target.samples[iter_idx % target.samples.size]
                   end

          # Generate mutated buffer
          mutated = target_engine.transform(sample)
          entropy = Inspector::Analyzer.calculate_entropy(mutated.to_slice)
          target_entropy_sum += entropy

          # Execute target test under watchdog timeout
          exec_start = Time.instant
          status, ex = execute_target(target, mutated)
          exec_duration = Time.instant - exec_start

          total_iters += 1
          current_iter = iter_idx + 1

          iter_result = IterationResult.new(
            target_name: target.name,
            iteration: current_iter,
            status: status,
            duration: exec_duration,
            input_size: sample.size,
            mutant_size: mutated.size,
            entropy: entropy,
            mutations_applied: target_engine.context.current_metadata.try(&.mutations_applied) || [] of String,
            error_class: ex.try(&.class.to_s),
            error_message: ex.try(&.message),
            backtrace: ex.try(&.backtrace?),
            mutant: mutated
          )

          case status
          when ExecutionStatus::Pass
            target_passes += 1
          when ExecutionStatus::ExpectedError
            target_expected_errors += 1
          when ExecutionStatus::Timeout
            target_timeouts += 1
            total_timeouts += 1
          when ExecutionStatus::Crash
            target_crashes += 1
            total_crashes += 1

            if err = ex
              record = create_crash_record(target, current_iter, err, mutated, entropy)
              if seen_crash_ids.add?(record.id)
                if @auto_shrink
                  shrink_crash_record(record, target)
                end
                crash_records << record
                @on_crash.try(&.call(record))
              end
            end
          when ExecutionStatus::Anomaly
            target_anomalies += 1
          end

          @on_progress.try(&.call(target.name, current_iter, @iterations_per_target, iter_result))

          # 60s Watchdog Heartbeat Invariant Check
          now = Time.utc
          if (now - last_watchdog) >= @watchdog_interval
            elapsed_sec = (now - started_at).total_seconds
            @on_heartbeat.try(&.call(total_iters, elapsed_sec))
            last_watchdog = now
          end
        end

        target_total_sec = (Time.utc - target_start).total_seconds
        target_ops = target_total_sec > 0.0 ? (target_passes + target_expected_errors + target_crashes + target_timeouts).to_f64 / target_total_sec : 0.0
        avg_entropy = @iterations_per_target > 0 ? (target_entropy_sum / @iterations_per_target).round(2) : 0.0

        target_summaries[target.name] = TargetSummary.new(
          target_name: target.name,
          category: target.category.to_s,
          iterations: target_passes + target_expected_errors + target_crashes + target_timeouts,
          passes: target_passes,
          expected_errors: target_expected_errors,
          crashes: target_crashes,
          timeouts: target_timeouts,
          anomalies: target_anomalies,
          total_time_ms: (target_total_sec * 1000.0).round(1),
          average_entropy: avg_entropy,
          throughput_ops_sec: target_ops.round(1)
        )
      end

      completed_at = Time.utc
      duration_sec = (completed_at - started_at).total_seconds
      overall_ops = duration_sec > 0.0 ? (total_iters.to_f64 / duration_sec).round(1) : 0.0

      CampaignReport.new(
        campaign_name: @name,
        started_at: started_at,
        completed_at: completed_at,
        total_iterations: total_iters,
        total_crashes: total_crashes,
        unique_crashes: crash_records.size,
        total_timeouts: total_timeouts,
        total_duration_seconds: duration_sec.round(2),
        overall_throughput_ops_sec: overall_ops,
        targets: target_summaries,
        crashes: crash_records
      )
    end

    private def execute_target(target : Target, mutant : Buffer) : Tuple(ExecutionStatus, Exception?)
      exec = target.execution
      return {ExecutionStatus::Pass, nil} unless exec

      # When timeout is zero or unbounded, execute directly in fiber
      if target.timeout <= Time::Span::ZERO
        begin
          exec.call(mutant)
          return {ExecutionStatus::Pass, nil}
        rescue ex
          if target.expected_error?(ex)
            return {ExecutionStatus::ExpectedError, ex}
          else
            return {ExecutionStatus::Crash, ex}
          end
        end
      end

      # Bounded execution with timeout
      ch = Channel(Tuple(ExecutionStatus, Exception?)).new(1)
      spawn do
        begin
          exec.call(mutant)
          ch.send({ExecutionStatus::Pass, nil})
        rescue ex
          if target.expected_error?(ex)
            ch.send({ExecutionStatus::ExpectedError, ex})
          else
            ch.send({ExecutionStatus::Crash, ex})
          end
        end
      end

      select
      when res = ch.receive
        res
      when timeout(target.timeout)
        {ExecutionStatus::Timeout, TimeoutError.new("Execution timed out after #{target.timeout.total_milliseconds}ms")}
      end
    end

    private def expired?(started_at : Time) : Bool
      if max = @max_duration
        (Time.utc - started_at) >= max
      else
        false
      end
    end

    private def create_crash_record(
      target : Target,
      iter : Int32,
      ex : Exception,
      mutant : Buffer,
      entropy : Float64,
    ) : CrashRecord
      bt = ex.backtrace? || ["(unknown backtrace)"]
      CrashRecord.new(
        target_name: target.name,
        iteration: iter,
        error_class: ex.class.to_s,
        error_message: ex.message || "(no message)",
        backtrace: bt,
        reproducer: mutant.dup,
        reproducer_entropy: entropy
      )
    end

    private def shrink_crash_record(record : CrashRecord, target : Target) : Nil
      exec = target.execution
      return unless exec

      # In-memory predicate testing whether candidate continues to trigger same unhandled crash
      pred = ->(cand : Buffer) {
        begin
          exec.call(cand)
          false
        rescue ex
          if target.expected_error?(ex)
            false
          else
            ex.class.to_s == record.error_class
          end
        end
      }

      reducer = Minimizer::Reducer.new(
        predicate: pred,
        timeout_ms: target.timeout.total_milliseconds.to_i
      )

      reduced = reducer.reduce(record.reproducer)
      if reduced.size < record.reproducer.size
        record.minimized_reproducer = reduced
        record.minimized_size = reduced.size
        record.minimized_base64 = Base64.strict_encode(reduced.to_slice)
      end
    rescue
      # Minimizer errors should not disrupt campaign
    end
  end

  class TimeoutError < Exception
  end
end
