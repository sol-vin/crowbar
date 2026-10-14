require "json"
require "base64"
require "digest/sha256"
require "../buffer"
require "../engine"
require "../inspector/analyzer"
require "../minimizer/reducer"
require "../campaign/result"
require "../campaign/runner"
require "../campaign/report"
require "../session"

module Crowbar::Core
  # Inviolable 60-Second Watchdog Law maximum budget
  MAX_WATCHDOG_BUDGET       = 60.seconds
  DEFAULT_WATCHDOG_BUDGET   = 60.seconds
  DEFAULT_WATCHDOG_INTERVAL = 10.seconds
  DEFAULT_SEED_TIMEOUT      = 500.milliseconds

  # Raised when a declarative invariant predicate returns false during seed replay
  class InvariantViolationError < Exception
    getter invariant_name : String

    def initialize(@invariant_name : String, message : String? = nil)
      super(message || "Regression invariant '#{@invariant_name}' failed")
    end
  end

  # Represents a deterministic seed or crash reproducer entry in a CorpusRunner
  struct CorpusSeed
    property id : String
    property payload : Buffer
    property seed : UInt64?
    property mutations : Int32
    property replay_verbatim : Bool
    property expected_errors : Array(Exception.class)
    getter sha256 : String
    getter base64 : String

    def initialize(
      @id : String,
      payload : Buffer | Bytes | String,
      @seed : UInt64? = nil,
      @mutations : Int32 = 0,
      @replay_verbatim : Bool = true,
      @expected_errors : Array(Exception.class) = [] of Exception.class,
    )
      @payload = case payload
                 when Buffer then payload.dup
                 when Bytes  then Buffer.new(payload)
                 else             Buffer.new(payload.to_s)
                 end
      @sha256 = Digest::SHA256.hexdigest(@payload.to_slice)
      @base64 = Base64.strict_encode(@payload.to_slice)
    end

    def size : Int32
      @payload.size
    end
  end

  alias SeedEntry = CorpusSeed

  # Outcome of replaying or mutating a single corpus seed
  struct SeedResult
    property seed_id : String
    property seed_value : UInt64
    property iteration : Int32
    property status : Campaign::ExecutionStatus
    property duration : Time::Span
    property payload_size : Int32
    property sha256 : String
    property mutations_applied : Array(String)
    property error_class : String?
    property error_message : String?
    property backtrace : Array(String)?
    property reproducer : Buffer?
    property minimized_reproducer : Buffer?

    def initialize(
      @seed_id : String,
      @seed_value : UInt64,
      @iteration : Int32,
      @status : Campaign::ExecutionStatus,
      @duration : Time::Span,
      @payload_size : Int32,
      @sha256 : String,
      @mutations_applied : Array(String) = [] of String,
      @error_class : String? = nil,
      @error_message : String? = nil,
      @backtrace : Array(String)? = nil,
      @reproducer : Buffer? = nil,
      @minimized_reproducer : Buffer? = nil,
    )
    end

    def passed? : Bool
      @status.pass? || @status.expected_error?
    end

    def clean? : Bool
      passed?
    end

    def crashed? : Bool
      @status.crash?
    end

    def timed_out? : Bool
      @status.timeout?
    end

    def failed? : Bool
      !passed?
    end

    def reproducer_base64 : String?
      @reproducer.try { |r| Base64.strict_encode(r.to_slice) }
    end

    def minimized_base64 : String?
      @minimized_reproducer.try { |r| Base64.strict_encode(r.to_slice) }
    end
  end

  # Summary report produced by a CorpusRunner regression gate execution
  class CorpusGateReport
    include JSON::Serializable

    getter gate_name : String
    getter started_at : Time
    getter completed_at : Time
    getter total_seeds : Int32
    getter total_executions : Int32
    getter passes : Int32
    getter expected_errors : Int32
    getter failures : Int32
    getter timeouts : Int32
    getter watchdog_budget_seconds : Float64
    getter watchdog_triggered : Bool
    getter heartbeats_emitted : Int32
    getter total_duration_seconds : Float64
    getter crashes : Array(Campaign::CrashRecord)

    @[JSON::Field(ignore: true)]
    getter results : Array(SeedResult) = [] of SeedResult

    def initialize(
      @gate_name : String,
      @started_at : Time,
      @completed_at : Time,
      @total_seeds : Int32,
      @total_executions : Int32,
      @passes : Int32,
      @expected_errors : Int32,
      @failures : Int32,
      @timeouts : Int32,
      @watchdog_budget_seconds : Float64,
      @watchdog_triggered : Bool,
      @heartbeats_emitted : Int32,
      @total_duration_seconds : Float64,
      @crashes : Array(Campaign::CrashRecord) = [] of Campaign::CrashRecord,
      @results : Array(SeedResult) = [] of SeedResult,
    )
    end

    def name : String
      @gate_name
    end

    def total_iterations : Int32
      @total_executions
    end

    def total_crashes : Int32
      @failures
    end

    def regressions : Int32
      @failures + @timeouts
    end

    def clean? : Bool
      @failures == 0 && @timeouts == 0 && !@watchdog_triggered
    end

    def passed? : Bool
      clean?
    end

    def within_budget? : Bool
      !@watchdog_triggered && @total_duration_seconds <= @watchdog_budget_seconds
    end

    def failed_results : Array(SeedResult)
      @results.select(&.failed?)
    end

    # Raises a RegressionError or WatchdogBudgetError if any seed failed or exceeded budget
    def assert_clean! : self
      if @watchdog_triggered
        raise WatchdogBudgetError.new(
          gate_name: @gate_name,
          budget: @watchdog_budget_seconds.seconds,
          elapsed: @total_duration_seconds.seconds,
          failures: failed_results,
          report: self
        )
      end

      unless clean?
        raise RegressionError.new(
          gate_name: @gate_name,
          failures: failed_results,
          report: self
        )
      end

      self
    end

    def verify! : self
      assert_clean!
    end

    # Renders a Markdown summary report for CI/CD logs and inspection
    def to_markdown : String
      String.build do |io|
        status_badge = clean? ? "PASS" : "FAIL"
        io << "# [Crowbar Corpus Gate: " << status_badge << "] " << @gate_name << "\n\n"
        io << "- **Started At**: `" << @started_at.to_rfc3339 << "`\n"
        io << "- **Completed At**: `" << @completed_at.to_rfc3339 << "`\n"
        io << "- **Duration**: `" << @total_duration_seconds << "s` (Watchdog Budget: `" << @watchdog_budget_seconds << "s`)\n"
        io << "- **Total Seeds**: `" << @total_seeds << "` | **Executions**: `" << @total_executions << "`\n"
        io << "- **Passes**: `" << @passes << "` | **Expected Errors**: `" << @expected_errors << "`\n"
        io << "- **Failures (Regressions)**: `" << @failures << "` | **Timeouts**: `" << @timeouts << "`\n"
        io << "- **Watchdog Triggered**: `" << @watchdog_triggered << "`\n"

        unless @crashes.empty?
          io << "\n## Regression Reproducers\n\n"
          io << "| ID | Seed / Target | Error Class | Message | Reproducer (Base64) |\n"
          io << "| :--- | :--- | :--- | :--- | :--- |\n"
          @crashes.each do |crash|
            b64 = crash.minimized_base64 || crash.reproducer_base64
            io << "| `" << crash.id << "` | `" << crash.target_name << "` (#" << crash.iteration << ") | `"
            io << crash.error_class << "` | " << crash.error_message.lines.first? << " | `" << b64 << "` |\n"
          end
        end
      end
    end
  end

  alias CorpusReport = CorpusGateReport

  # Raised when one or more seeds trigger an unhandled crash, timeout, or invariant failure
  class RegressionError < Exception
    getter gate_name : String
    getter failures : Array(SeedResult)
    getter report : CorpusGateReport?

    def initialize(
      @gate_name : String,
      @failures : Array(SeedResult) = [] of SeedResult,
      @report : CorpusGateReport? = nil,
      message : String? = nil,
    )
      super(message || build_diagnostic_message)
    end

    private def build_diagnostic_message : String
      String.build do |io|
        io << "Crowbar Corpus Gate '" << @gate_name << "' failed with " << @failures.size << " regression(s):\n"
        @failures.first(5).each_with_index do |fail, idx|
          io << "  [" << (idx + 1) << "] Seed '" << fail.seed_id << "' (seed=" << fail.seed_value
          io << ", iter=" << fail.iteration << ", status=" << fail.status << "):\n"
          io << "      Error: " << (fail.error_class || "UnknownError") << ": " << (fail.error_message || "(no message)") << "\n"
          io << "      SHA-256: " << fail.sha256 << " (" << fail.payload_size << " bytes)\n"
          if min_b64 = fail.minimized_base64
            io << "      Minimized Reproducer (Base64): " << min_b64 << "\n"
          elsif rep_b64 = fail.reproducer_base64
            io << "      Reproducer (Base64): " << rep_b64 << "\n"
          end
        end
      end
    end
  end

  # Raised when a CorpusRunner execution exceeds the 60-second watchdog budget
  class WatchdogBudgetError < RegressionError
    getter budget : Time::Span
    getter elapsed : Time::Span

    def initialize(
      gate_name : String,
      @budget : Time::Span,
      @elapsed : Time::Span,
      failures : Array(SeedResult) = [] of SeedResult,
      report : CorpusGateReport? = nil,
    )
      msg = "Crowbar Corpus Gate '#{gate_name}' exceeded watchdog budget of #{@budget.total_seconds}s (elapsed: #{@elapsed.total_seconds.round(3)}s)"
      super(gate_name, failures, report, msg)
    end
  end

  # Raised when deterministic replay verification detects non-deterministic mutation output
  class DeterminismError < RegressionError
  end

  # Tier 1 Core Engine: Deterministic seed replay and crash regression verification runner
  # operating under a strict <= 60-second watchdog budget.
  class CorpusRunner
    property name : String
    property seeds : Array(CorpusSeed)
    property deterministic_seeds : Array(UInt64)
    property base_seed : UInt64
    property iterations : Int32
    property mutations_per_seed : Int32
    property rules : Array(Rule)
    property scopes : Array(Scope)
    property fixups : Array(Proc(Buffer, Nil))
    property pattern : Pattern
    property expected_errors : Array(Exception.class)
    property forbidden_errors : Array(Exception.class)
    property invariants : Array(Tuple(String, Proc(Buffer, Bool)))
    property assertions : Array(Tuple(String, Proc(Buffer, Nil)))
    property per_seed_timeout : Time::Span
    getter watchdog_budget : Time::Span
    property watchdog_interval : Time::Span
    property auto_shrink : Bool
    property fail_fast : Bool
    property verify_determinism : Bool
    property execution : Proc(Buffer, Nil)?

    # Telemetry and lifecycle callbacks
    property on_heartbeat : Proc(Int32, Float64, Nil)?
    property on_seed_complete : Proc(SeedResult, Nil)?
    property on_regression : Proc(SeedResult, Nil)?

    def initialize(
      @name : String = "Corpus Regression Gate",
      @seeds : Array(CorpusSeed) = [] of CorpusSeed,
      @deterministic_seeds : Array(UInt64) = [] of UInt64,
      @base_seed : UInt64 = 42_u64,
      @iterations : Int32 = 0,
      @mutations_per_seed : Int32 = 0,
      @rules : Array(Rule) = [] of Rule,
      @expected_errors : Array(Exception.class) = [] of Exception.class,
      @per_seed_timeout : Time::Span = DEFAULT_SEED_TIMEOUT,
      watchdog_budget : Time::Span = DEFAULT_WATCHDOG_BUDGET,
      @watchdog_interval : Time::Span = DEFAULT_WATCHDOG_INTERVAL,
      @auto_shrink : Bool = true,
      @fail_fast : Bool = false,
      @verify_determinism : Bool = false,
      @execution : Proc(Buffer, Nil)? = nil,
    )
      @scopes = [] of Scope
      @fixups = [] of Proc(Buffer, Nil)
      @pattern = Patterns::Many.new
      @forbidden_errors = [] of Exception.class
      @invariants = [] of Tuple(String, Proc(Buffer, Bool))
      @assertions = [] of Tuple(String, Proc(Buffer, Nil))
      @watchdog_budget = DEFAULT_WATCHDOG_BUDGET
      self.watchdog_budget = watchdog_budget
    end

    # Enforces the Inviolable 60-Second Watchdog Law (0 < budget <= 60s)
    def watchdog_budget=(budget : Time::Span) : Time::Span
      if budget <= Time::Span::ZERO
        raise ArgumentError.new("Watchdog budget must be positive (got #{budget})")
      end
      if budget > MAX_WATCHDOG_BUDGET
        raise ArgumentError.new("Watchdog budget cannot exceed 60 seconds (Inviolable 60-Second Watchdog Law, got #{budget.total_seconds}s)")
      end
      @watchdog_budget = budget
    end

    def timeout : Time::Span
      @per_seed_timeout
    end

    def timeout=(span : Time::Span) : Time::Span
      @per_seed_timeout = span
    end

    # Registers a corpus seed or crash reproducer for deterministic replay
    def add_seed(
      payload : Buffer | Bytes | String,
      id : String? = nil,
      seed : UInt64? = nil,
      mutations : Int32 = 0,
      replay_verbatim : Bool = true,
      expected_errors : Array(Exception.class) = [] of Exception.class,
    ) : CorpusSeed
      seed_id = id || "seed_#{@seeds.size + 1}"
      entry = CorpusSeed.new(
        id: seed_id,
        payload: payload,
        seed: seed,
        mutations: mutations,
        replay_verbatim: replay_verbatim,
        expected_errors: expected_errors
      )
      @seeds << entry
      entry
    end

    # Registers a Base64-encoded crash reproducer or seed payload
    def add_base64_seed(
      b64 : String,
      id : String? = nil,
      seed : UInt64? = nil,
      mutations : Int32 = 0,
    ) : CorpusSeed
      decoded = Base64.decode(b64.strip)
      add_seed(decoded, id: id || "b64_seed_#{@seeds.size + 1}", seed: seed, mutations: mutations)
    end

    # Registers a hex-encoded crash reproducer or seed payload
    def add_hex_seed(
      hex : String,
      id : String? = nil,
      seed : UInt64? = nil,
      mutations : Int32 = 0,
    ) : CorpusSeed
      clean_hex = hex.gsub(/\s+/, "")
      decoded = clean_hex.hexbytes
      add_seed(decoded, id: id || "hex_seed_#{@seeds.size + 1}", seed: seed, mutations: mutations)
    end

    # Registers a deterministic (PRNG seed, baseline input) mutation replay pair
    def add_replay(
      seed_val : UInt64,
      payload : Buffer | Bytes | String,
      id : String? = nil,
      mutations : Int32 = 1,
    ) : CorpusSeed
      seed_id = id || "replay_#{seed_val}_#{@seeds.size + 1}"
      entry = CorpusSeed.new(
        id: seed_id,
        payload: payload,
        seed: seed_val,
        mutations: mutations < 1 ? 1 : mutations,
        replay_verbatim: false
      )
      @seeds << entry
      entry
    end

    # Registers an explicit PRNG seed for deterministic mutation replay across corpus baselines
    def add_deterministic_seed(seed_val : UInt64) : Nil
      @deterministic_seeds << seed_val unless @deterministic_seeds.includes?(seed_val)
    end

    # Imports a CrashRecord (minimized or full reproducer) from a Campaign run
    def add_crash_record(record : Campaign::CrashRecord) : CorpusSeed
      payload = record.minimized_reproducer || record.reproducer
      add_seed(payload, id: "crash_#{record.target_name}_#{record.id}")
    end

    # Deterministically loads corpus files from a directory (sorted lexicographically)
    def load_directory(dir_path : String, pattern : String = "*") : Int32
      return 0 unless Dir.exists?(dir_path)
      matched = Dir.children(dir_path).select do |entry|
        full = File.join(dir_path, entry)
        File.file?(full) && (pattern == "*" || File.match?(pattern, entry))
      end.sort!

      matched.each do |entry|
        full = File.join(dir_path, entry)
        bytes = File.read(full).to_slice
        add_seed(bytes, id: entry)
      end
      matched.size
    end

    # Loads corpus candidates and recorded session items from a persistent Crowbar::Session
    def load_session(session : Session) : Int32
      added = 0
      # Always include baseline
      add_seed(session.baseline, id: "#{session.id}_baseline", seed: session.seed)
      added += 1

      session.corpus_items.each_with_index do |cand, idx|
        decoded = Base64.decode(cand.buffer_b64)
        add_seed(decoded, id: "#{session.id}_corpus_#{idx + 1}")
        added += 1
      end

      session.items.each do |item|
        if buf = session.get_mutant(item.iteration)
          add_seed(buf, id: "#{session.id}_iter_#{item.iteration}", seed: item.seed)
          added += 1
        end
      end
      added
    end

    def add_rule(rule : Rule) : Nil
      @rules << rule
    end

    def add_scope(scope : Scope) : Nil
      @scopes << scope
    end

    def add_fixup(&block : Buffer -> Nil) : Nil
      @fixups << block
    end

    def add_expected_error(err_class : Exception.class) : Nil
      @expected_errors << err_class unless @expected_errors.includes?(err_class)
    end

    def add_forbidden_error(err_class : Exception.class) : Nil
      @forbidden_errors << err_class unless @forbidden_errors.includes?(err_class)
    end

    def add_invariant(name : String = "invariant_#{@invariants.size + 1}", &block : Buffer -> Bool) : Nil
      @invariants << {name, block}
    end

    def add_assertion(name : String = "assertion_#{@assertions.size + 1}", &block : Buffer -> Nil) : Nil
      @assertions << {name, block}
    end

    def expected_error?(ex : Exception, seed_expected : Array(Exception.class) = [] of Exception.class) : Bool
      return false if @forbidden_errors.any? { |cls| ex.class <= cls }
      @expected_errors.any? { |cls| ex.class <= cls } || seed_expected.any? { |cls| ex.class <= cls }
    end

    # Generates the deterministic mutation of `input` for a given `seed_val` and step count
    def generate_deterministic_mutant(input : Buffer | Bytes | String, seed_val : UInt64, steps : Int32 = 1) : Tuple(Buffer, Array(String))
      eng = build_engine(seed_val)
      current = case input
                when Buffer then input.dup
                when Bytes  then Buffer.new(input)
                else             Buffer.new(input.to_s)
                end
      applied = [] of String
      steps.times do
        current = eng.transform(current)
        if meta = eng.context.current_metadata
          applied.concat(meta.mutations_applied)
        end
      end
      {current, applied}
    end

    # Replays a single deterministic (seed, input) mutation on demand
    def replay(seed_val : UInt64, input : Buffer | Bytes | String, steps : Int32 = 1) : SeedResult
      mutant, applied = generate_deterministic_mutant(input, seed_val, steps)
      execute_buffer(
        buffer: mutant,
        seed_id: "replay_#{seed_val}",
        seed_value: seed_val,
        iteration: 1,
        mutations_applied: applied
      )
    end

    # Executes the full corpus regression gate and raises RegressionError if not clean
    def run! : CorpusGateReport
      run.assert_clean!
    end

    # Executes the full corpus regression gate under the <= 60s watchdog budget
    def run : CorpusGateReport
      started_at = Time.utc
      started_instant = Time.instant
      last_watchdog = started_instant
      heartbeats = 0
      watchdog_triggered = false

      results = [] of SeedResult
      crash_records = [] of Campaign::CrashRecord
      seen_crash_ids = Set(String).new

      passes = 0
      expected_errs = 0
      failures = 0
      timeouts = 0
      exec_count = 0

      # Optional determinism verification check before main execution
      if @verify_determinism
        verify_deterministic_generation!(started_at)
      end

      # Helper closure to record each SeedResult and check watchdog/fail-fast invariants
      record_result = ->(res : SeedResult) {
        results << res
        exec_count += 1

        case res.status
        when Campaign::ExecutionStatus::Pass
          passes += 1
        when Campaign::ExecutionStatus::ExpectedError
          expected_errs += 1
        when Campaign::ExecutionStatus::Timeout
          timeouts += 1
          @on_regression.try(&.call(res))
        when Campaign::ExecutionStatus::Crash, Campaign::ExecutionStatus::Anomaly
          failures += 1
          if rep = res.reproducer
            entropy = Inspector::Analyzer.calculate_entropy(rep.to_slice)
            crash_rec = Campaign::CrashRecord.new(
              target_name: res.seed_id,
              iteration: res.iteration,
              error_class: res.error_class || "RegressionFailure",
              error_message: res.error_message || "(unhandled failure)",
              backtrace: res.backtrace || ["(no backtrace)"],
              reproducer: rep.dup,
              reproducer_entropy: entropy,
              minimized_reproducer: res.minimized_reproducer
            )
            if seen_crash_ids.add?(crash_rec.id)
              crash_records << crash_rec
            end
          end
          @on_regression.try(&.call(res))
        end

        @on_seed_complete.try(&.call(res))

        # Emit periodic 60s watchdog heartbeat
        now_inst = Time.instant
        if (now_inst - last_watchdog) >= @watchdog_interval
          heartbeats += 1
          elapsed_sec = (now_inst - started_instant).total_seconds
          @on_heartbeat.try(&.call(exec_count, elapsed_sec))
          last_watchdog = now_inst
        end

        if (now_inst - started_instant) >= @watchdog_budget
          watchdog_triggered = true
        end
      }

      abort_gate = -> : Bool {
        if (Time.instant - started_instant) >= @watchdog_budget
          watchdog_triggered = true
          return true
        end
        if @fail_fast && (failures > 0 || timeouts > 0)
          return true
        end
        false
      }

      # Phase 1: Replay all registered CorpusSeeds (verbatim and/or per-seed mutations)
      @seeds.each_with_index do |seed_entry, idx|
        break if abort_gate.call

        effective_seed = seed_entry.seed || (@base_seed &+ idx.to_u64)

        if seed_entry.replay_verbatim
          res = execute_buffer(
            buffer: seed_entry.payload.dup,
            seed_id: seed_entry.id,
            seed_value: effective_seed,
            iteration: exec_count + 1,
            mutations_applied: [] of String,
            seed_expected: seed_entry.expected_errors
          )
          record_result.call(res)
        end

        mut_count = seed_entry.mutations > 0 ? seed_entry.mutations : @mutations_per_seed
        if mut_count > 0 && !abort_gate.call
          eng = build_engine(effective_seed)
          mut_count.times do |m_idx|
            break if abort_gate.call
            mutated = eng.transform(seed_entry.payload)
            applied = eng.context.current_metadata.try(&.mutations_applied) || [] of String
            res = execute_buffer(
              buffer: mutated,
              seed_id: "#{seed_entry.id}:mut_#{m_idx + 1}",
              seed_value: effective_seed,
              iteration: exec_count + 1,
              mutations_applied: applied,
              seed_expected: seed_entry.expected_errors
            )
            record_result.call(res)
          end
        end
      end

      # Phase 2: Replay explicit deterministic PRNG seed list across baseline corpus
      unless @deterministic_seeds.empty?
        @deterministic_seeds.each_with_index do |det_seed, s_idx|
          break if abort_gate.call
          baseline = if @seeds.empty?
                       Buffer.new("default_corpus_seed_#{@name}")
                     else
                       @seeds[s_idx % @seeds.size].payload
                     end
          mutated, applied = generate_deterministic_mutant(baseline, det_seed, 1)
          res = execute_buffer(
            buffer: mutated,
            seed_id: "seed_0x#{det_seed.to_s(16)}",
            seed_value: det_seed,
            iteration: exec_count + 1,
            mutations_applied: applied
          )
          record_result.call(res)
        end
      end

      # Phase 3: Execute configured deterministic PRNG mutation iterations
      if @iterations > 0 && !abort_gate.call
        eng = build_engine(@base_seed)
        @iterations.times do |iter_idx|
          break if abort_gate.call
          sample = if @seeds.empty?
                     Buffer.new("default_corpus_seed_#{@name}")
                   else
                     @seeds[iter_idx % @seeds.size].payload
                   end
          mutated = eng.transform(sample)
          applied = eng.context.current_metadata.try(&.mutations_applied) || [] of String
          iter_seed = @base_seed &+ iter_idx.to_u64
          res = execute_buffer(
            buffer: mutated,
            seed_id: "iter_#{iter_idx + 1}",
            seed_value: iter_seed,
            iteration: exec_count + 1,
            mutations_applied: applied
          )
          record_result.call(res)
        end
      end

      # Ensure at least one heartbeat is emitted on completion if callback is registered
      if @on_heartbeat && heartbeats == 0
        heartbeats += 1
        elapsed_sec = (Time.instant - started_instant).total_seconds
        @on_heartbeat.try(&.call(exec_count, elapsed_sec))
      end

      completed_at = Time.utc
      total_sec = (Time.instant - started_instant).total_seconds

      CorpusGateReport.new(
        gate_name: @name,
        started_at: started_at,
        completed_at: completed_at,
        total_seeds: @seeds.size + @deterministic_seeds.size,
        total_executions: exec_count,
        passes: passes,
        expected_errors: expected_errs,
        failures: failures,
        timeouts: timeouts,
        watchdog_budget_seconds: @watchdog_budget.total_seconds,
        watchdog_triggered: watchdog_triggered,
        heartbeats_emitted: heartbeats,
        total_duration_seconds: total_sec.round(4),
        crashes: crash_records,
        results: results
      )
    end

    private def build_engine(seed_val : UInt64) : Engine
      eng = Engine.new(seed_val)
      @rules.each { |r| eng.add_rule(r) }
      @scopes.each { |s| eng.add_scope(s) }
      @fixups.each { |f| eng.add_fixup(&f) }
      eng.pattern = @pattern
      eng
    end

    private def verify_deterministic_generation!(started_at : Time) : Nil
      sample = @seeds.first?.try(&.payload) || Buffer.new("determinism_probe_#{@name}")
      probe_seeds = @deterministic_seeds.empty? ? [@base_seed, @base_seed &+ 1_u64] : @deterministic_seeds.first(3)

      probe_seeds.each do |s_val|
        out_a, _ = generate_deterministic_mutant(sample, s_val, 1)
        out_b, _ = generate_deterministic_mutant(sample, s_val, 1)
        if out_a != out_b
          raise DeterminismError.new(
            gate_name: @name,
            message: "Non-deterministic mutation detected for seed #{s_val} in gate '#{@name}'"
          )
        end
      end
    end

    private def execute_buffer(
      buffer : Buffer,
      seed_id : String,
      seed_value : UInt64,
      iteration : Int32,
      mutations_applied : Array(String),
      seed_expected : Array(Exception.class) = [] of Exception.class,
    ) : SeedResult
      sha = Digest::SHA256.hexdigest(buffer.to_slice)
      exec_start = Time.instant
      status, ex = run_with_timeout(buffer, seed_expected)
      duration = Time.instant - exec_start

      reproducer : Buffer? = nil
      minimized : Buffer? = nil

      if status.crash? || status.timeout?
        reproducer = buffer.dup
        if status.crash? && @auto_shrink && ex
          minimized = shrink_failure(buffer, ex, seed_expected)
        end
      end

      SeedResult.new(
        seed_id: seed_id,
        seed_value: seed_value,
        iteration: iteration,
        status: status,
        duration: duration,
        payload_size: buffer.size,
        sha256: sha,
        mutations_applied: mutations_applied,
        error_class: ex.try(&.class.to_s),
        error_message: ex.try(&.message),
        backtrace: ex.try(&.backtrace?),
        reproducer: reproducer,
        minimized_reproducer: minimized
      )
    end

    private def run_with_timeout(
      buffer : Buffer,
      seed_expected : Array(Exception.class),
    ) : Tuple(Campaign::ExecutionStatus, Exception?)
      if @per_seed_timeout <= Time::Span::ZERO
        return invoke_target_and_assertions(buffer, seed_expected)
      end

      ch = Channel(Tuple(Campaign::ExecutionStatus, Exception?)).new(1)
      spawn do
        res = invoke_target_and_assertions(buffer, seed_expected)
        ch.send(res)
      end

      select
      when res = ch.receive
        res
      when timeout(@per_seed_timeout)
        {
          Campaign::ExecutionStatus::Timeout,
          Campaign::TimeoutError.new("Seed execution timed out after #{@per_seed_timeout.total_milliseconds}ms"),
        }
      end
    end

    private def invoke_target_and_assertions(
      buffer : Buffer,
      seed_expected : Array(Exception.class),
    ) : Tuple(Campaign::ExecutionStatus, Exception?)
      begin
        # 1. Execute primary target block if present
        if exec = @execution
          exec.call(buffer)
        end

        # 2. Check all registered boolean invariants
        @invariants.each do |inv_name, predicate|
          unless predicate.call(buffer)
            return {
              Campaign::ExecutionStatus::Crash,
              InvariantViolationError.new(inv_name, "Regression invariant '#{inv_name}' returned false"),
            }
          end
        end

        # 3. Run all registered spec/assertion blocks
        @assertions.each do |_, assertion_proc|
          assertion_proc.call(buffer)
        end

        {Campaign::ExecutionStatus::Pass, nil}
      rescue ex : InvariantViolationError
        {Campaign::ExecutionStatus::Crash, ex}
      rescue ex
        if expected_error?(ex, seed_expected)
          {Campaign::ExecutionStatus::ExpectedError, ex}
        else
          {Campaign::ExecutionStatus::Crash, ex}
        end
      end
    end

    private def shrink_failure(
      buffer : Buffer,
      original_ex : Exception,
      seed_expected : Array(Exception.class),
    ) : Buffer?
      target_err_class = original_ex.class.to_s
      pred = ->(cand : Buffer) {
        status, ex = invoke_target_and_assertions(cand, seed_expected)
        status.crash? && ex.try(&.class.to_s) == target_err_class
      }

      reducer = Minimizer::Reducer.new(
        predicate: pred,
        timeout_ms: @per_seed_timeout.total_milliseconds.to_i
      )
      reduced = reducer.reduce(buffer)
      reduced.size < buffer.size ? reduced : nil
    rescue
      nil
    end
  end
end
