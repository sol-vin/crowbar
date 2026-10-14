require "./spec_helper"
require "file_utils"
require "json"
require "csv"

class CustomParserError < Exception; end

class CriticalMemoryCorruptionError < CustomParserError; end

describe Crowbar::Core::CorpusRunner do
  describe "60-Second Watchdog Budget Invariant" do
    it "defaults to a 60-second watchdog budget and enforces 0 < budget <= 60s" do
      runner = Crowbar::Core::CorpusRunner.new("Watchdog Invariant Test")
      runner.watchdog_budget.should eq(60.seconds)

      runner.watchdog_budget = 30.seconds
      runner.watchdog_budget.should eq(30.seconds)

      expect_raises(ArgumentError, /cannot exceed 60 seconds/) do
        runner.watchdog_budget = 61.seconds
      end

      expect_raises(ArgumentError, /must be positive/) do
        runner.watchdog_budget = 0.seconds
      end
    end

    it "emits periodic watchdog heartbeats during execution" do
      heartbeats = 0
      runner = Crowbar::Core::CorpusRunner.new(
        name: "Heartbeat Runner",
        watchdog_budget: 10.seconds,
        watchdog_interval: 1.millisecond
      )
      5.times { |i| runner.add_seed("seed_payload_#{i}") }
      runner.execution = ->(buf : Crowbar::Buffer) {
        sleep 2.milliseconds
        nil
      }
      runner.on_heartbeat = ->(count : Int32, elapsed : Float64) {
        heartbeats += 1
      }

      report = runner.run
      report.clean?.should be_true
      report.total_executions.should eq(5)
      heartbeats.should be > 0
      report.heartbeats_emitted.should be > 0
    end

    it "aborts and flags watchdog_triggered when execution exceeds configured budget" do
      runner = Crowbar::Core::CorpusRunner.new(
        name: "Budget Breach Gate",
        watchdog_budget: 15.milliseconds,
        per_seed_timeout: 100.milliseconds
      )
      20.times { |i| runner.add_seed("slow_seed_#{i}") }
      runner.execution = ->(buf : Crowbar::Buffer) {
        sleep 10.milliseconds
        nil
      }

      report = runner.run
      report.watchdog_triggered.should be_true
      report.clean?.should be_false
      report.total_executions.should be < 20

      expect_raises(Crowbar::Core::WatchdogBudgetError, /exceeded watchdog budget/) do
        report.assert_clean!
      end
    end
  end

  describe "Deterministic Seed Replay & Encoding Helpers" do
    it "computes SHA-256 digests and replays raw, Base64, and hex seeds verbatim" do
      seen_payloads = [] of String
      runner = Crowbar::Core::CorpusRunner.new("Verbatim Seed Replay")

      s1 = runner.add_seed("alpha_payload", id: "raw_alpha")
      s2 = runner.add_base64_seed(Base64.strict_encode("beta_payload"), id: "b64_beta")
      s3 = runner.add_hex_seed("67616d6d61", id: "hex_gamma") # "gamma"

      s1.sha256.should eq(Digest::SHA256.hexdigest("alpha_payload"))
      s2.payload.to_s.should eq("beta_payload")
      s3.payload.to_s.should eq("gamma")

      runner.execution = ->(buf : Crowbar::Buffer) {
        seen_payloads << buf.to_s
        nil
      }

      report = runner.run!
      report.clean?.should be_true
      report.total_executions.should eq(3)
      seen_payloads.should eq(["alpha_payload", "beta_payload", "gamma"])
    end

    it "produces identical mutation sequences across runs for identical PRNG seeds" do
      run_sequence = ->(seed_val : UInt64) {
        captured = [] of String
        runner = Crowbar::Core::CorpusRunner.new(
          name: "Determinism Check",
          base_seed: seed_val,
          iterations: 10,
          verify_determinism: true
        )
        runner.add_seed(%({"id": 100, "status": "ok"}), id: "json_base")
        runner.add_rule(Crowbar::Rules::JSONRule.new)
        runner.execution = ->(buf : Crowbar::Buffer) {
          captured << Digest::SHA256.hexdigest(buf.to_slice)
          nil
        }
        runner.run!
        captured
      }

      seq_a = run_sequence.call(0xCAFEBABE_u64)
      seq_b = run_sequence.call(0xCAFEBABE_u64)
      seq_c = run_sequence.call(0xDEADBEEF_u64)

      seq_a.size.should eq(11) # 1 verbatim + 10 deterministic iterations
      seq_a.should eq(seq_b)
      seq_a.should_not eq(seq_c)
    end

    it "replays specific (seed, input) pairs on demand via runner.replay" do
      runner = Crowbar::Core::CorpusRunner.new("On-Demand Replay")
      runner.add_rule(Crowbar::Rules::JSONRule.new)

      observed = ""
      runner.execution = ->(buf : Crowbar::Buffer) {
        observed = buf.to_s
        JSON.parse(observed)
        nil
      }

      res1 = runner.replay(1337_u64, %({"count": 42, "active": true}))
      first_observed = observed

      res2 = runner.replay(1337_u64, %({"count": 42, "active": true}))
      second_observed = observed

      res1.passed?.should be_true
      res2.passed?.should be_true
      first_observed.should eq(second_observed)
      res1.sha256.should eq(res2.sha256)
    end

    it "loads corpus files deterministically from a directory and from a Session" do
      temp_dir = File.join(Dir.tempdir, "crowbar_corpus_gate_#{Random.rand(100_000)}")
      FileUtils.mkdir_p(temp_dir)

      begin
        File.write(File.join(temp_dir, "02_second.txt"), "second_seed")
        File.write(File.join(temp_dir, "01_first.txt"), "first_seed")

        sess = Crowbar::Session.new("gate_sess", Crowbar::Buffer.new("session_baseline_seed"), seed: 99_u64)
        sess.save(temp_dir)
        sess.next_mutant(dir: temp_dir)

        replayed_ids = [] of String
        runner = Crowbar::Core::CorpusRunner.new("Dir and Session Loader")
        loaded_files = runner.load_directory(temp_dir, "*.txt")
        loaded_files.should eq(2)

        loaded_sess = runner.load_session(sess)
        loaded_sess.should be >= 2

        runner.execution = ->(buf : Crowbar::Buffer) { nil }
        runner.on_seed_complete = ->(res : Crowbar::Core::SeedResult) {
          replayed_ids << res.seed_id
        }

        report = runner.run!
        report.clean?.should be_true
        replayed_ids[0].should eq("01_first.txt")
        replayed_ids[1].should eq("02_second.txt")
        replayed_ids.should contain("gate_sess_baseline")
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end

  describe "Regression Detection, Expected/Forbidden Errors & Minimization" do
    it "distinguishes expected errors from forbidden or unhandled crashes and shrinks reproducers" do
      runner = Crowbar::Core::CorpusRunner.new(
        name: "Exception Classification Gate",
        auto_shrink: true
      )
      runner.add_expected_error(CustomParserError)
      runner.add_forbidden_error(CriticalMemoryCorruptionError)

      runner.add_seed("SAFE_INPUT", id: "seed_safe")
      runner.add_seed("EXPECTED_ERR_INPUT", id: "seed_expected")
      runner.add_seed("xxxx_PANIC_BUG_yyyyzzzz", id: "seed_forbidden")

      runner.execution = ->(buf : Crowbar::Buffer) {
        str = buf.to_s
        if str.includes?("PANIC_BUG")
          raise CriticalMemoryCorruptionError.new("Heap corruption triggered")
        elsif str.includes?("EXPECTED_ERR")
          raise CustomParserError.new("Handled syntax error")
        end
        nil
      }

      report = runner.run
      report.clean?.should be_false
      report.passes.should eq(1)
      report.expected_errors.should eq(1)
      report.failures.should eq(1)
      report.crashes.size.should eq(1)

      failed = report.failed_results.first
      failed.seed_id.should eq("seed_forbidden")
      failed.error_class.should eq("CriticalMemoryCorruptionError")
      # Minimizer should reduce surrounding padding down to "PANIC_BUG"
      min_buf = failed.minimized_reproducer.not_nil!
      min_buf.to_s.should eq("PANIC_BUG")

      expect_raises(Crowbar::Core::RegressionError, /CriticalMemoryCorruptionError/) do
        report.assert_clean!
      end
    end
  end
end

describe "Declarative DSL: Crowbar.corpus_gate" do
  it "executes a clean deterministic regression gate inside crystal spec under a 60s watchdog budget" do
    executed_count = 0

    report = Crowbar.corpus_gate("JSON & Header Protocol Regression Gate") do |gate|
      gate.watchdog_budget 60.seconds
      gate.timeout 250.milliseconds
      gate.seed 42_u64
      gate.seeds 101_u64, 202_u64
      gate.iterations 10
      gate.mutations_per_seed 2
      gate.preserve :json
      gate.expected_errors JSON::ParseException, ArgumentError

      gate.corpus %({"version": 1, "items": [1, 2, 3]}), id: "valid_v1"
      gate.reproducer_base64 Base64.strict_encode(%({"version": 2, "empty": {}})), id: "b64_v2"
      gate.replay 777_u64, %({"replay": true}), id: "seeded_replay"

      gate.execute do |buf|
        executed_count += 1
        JSON.parse(buf.to_s)
      end

      gate.assert_invariant("non_empty_json_output") do |buf|
        buf.size > 0
      end

      gate.assert("valid_utf8_invariant") do |buf|
        buf.to_s.valid_encoding?.should be_true
      end
    end

    report.clean?.should be_true
    report.passed?.should be_true
    report.within_budget?.should be_true
    report.watchdog_budget_seconds.should eq(60.0)
    # 2 verbatim seeds + (2 * 2 mutations_per_seed) + (1 replay * 2 mutations_per_seed) + 2 explicit seeds + 10 iterations = 20
    report.total_executions.should eq(executed_count)
    executed_count.should be >= 18

    md = report.to_markdown
    md.should contain("[Crowbar Corpus Gate: PASS] JSON & Header Protocol Regression Gate")
    JSON.parse(report.to_json)["gate_name"].as_s.should eq("JSON & Header Protocol Regression Gate")
  end

  it "raises Crowbar::Core::RegressionError when an invariant or spec assertion fails" do
    expect_raises(Crowbar::Core::RegressionError, /Regression invariant 'no_magic_trap'/) do
      Crowbar.corpus_gate("Failing Invariant Gate") do |gate|
        gate.watchdog_budget 30.seconds
        gate.auto_shrink false
        gate.corpus "normal_seed"
        gate.reproducer "TRIGGER_TRAP_PAYLOAD", id: "trap_seed"

        gate.execute do |buf|
          # Target does not raise, but invariant catches the regression
        end

        gate.assert_invariant("no_magic_trap") do |buf|
          !buf.to_s.includes?("TRIGGER_TRAP")
        end
      end
    end
  end

  it "supports non-throwing inspection mode when assert_clean is false" do
    report = Crowbar.corpus_gate("Non-Throwing Gate", assert_clean: false) do |gate|
      gate.auto_shrink false
      gate.reproducer "BOOM", id: "boom_seed"
      gate.execute do |buf|
        raise RuntimeError.new("Boom failure") if buf.to_s == "BOOM"
      end
    end

    report.clean?.should be_false
    report.failures.should eq(1)
    report.failed_results.first.seed_id.should eq("boom_seed")
  end

  it "supports Crowbar.define_corpus_gate for reusable runner construction" do
    runner = Crowbar.define_corpus_gate("Reusable Gate") do |gate|
      gate.seed 12345_u64
      gate.watchdog_budget 45.seconds
      gate.sample "hello=world"
      gate.execute do |buf|
        buf.size.should be >= 0
      end
    end

    runner.should be_a(Crowbar::Core::CorpusRunner)
    runner.name.should eq("Reusable Gate")
    runner.watchdog_budget.should eq(45.seconds)
    report = runner.run!
    report.clean?.should be_true
  end
end
