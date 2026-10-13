require "./spec_helper"
require "../src/crowbar/cli/app"

describe Crowbar::Campaign do
  describe Crowbar::Campaign::Target do
    it "configures target properties and samples correctly" do
      target = Crowbar::Campaign::Target.new(
        name: "test_target",
        category: Crowbar::Campaign::TargetCategory::Serialization,
        expected_errors: [JSON::ParseException] of Exception.class,
        timeout: 100.milliseconds
      )
      target.add_sample(%({"key": "value"}))
      target.add_rule(Crowbar::Rules::JSONRule.new)

      target.name.should eq("test_target")
      target.category.should eq(Crowbar::Campaign::TargetCategory::Serialization)
      target.samples.size.should eq(1)
      target.rules.size.should eq(1)
      target.expected_error?(JSON::ParseException.new("parse error", 1, 1)).should be_true
      target.expected_error?(ArgumentError.new("invalid")).should be_false
    end
  end

  describe Crowbar::Campaign::Runner do
    it "executes iterations and reports clean status when no unhandled crashes occur" do
      target = Crowbar::Campaign::Target.new(
        name: "safe_target",
        category: Crowbar::Campaign::TargetCategory::Custom,
        expected_errors: [ArgumentError] of Exception.class,
        timeout: 50.milliseconds
      )
      target.add_sample("test data 12345")
      target.execution = ->(buf : Crowbar::Buffer) {
        # Valid execution, no crash
        if buf.size % 2 == 0
          raise ArgumentError.new("Even size argument error")
        end
        nil
      }

      runner = Crowbar::Campaign::Runner.new(
        name: "Test Runner",
        targets: [target],
        iterations_per_target: 20,
        seed: 1234_u64,
        auto_shrink: false
      )

      report = runner.run
      report.clean?.should be_true
      report.total_iterations.should eq(20)
      report.total_crashes.should eq(0)
      report.targets["safe_target"].iterations.should eq(20)
      report.targets["safe_target"].crashes.should eq(0)
      report.targets["safe_target"].passes.should be > 0
      report.targets["safe_target"].expected_errors.should be > 0
    end

    it "catches unhandled crashes, records reproducers, and minimizes them" do
      target = Crowbar::Campaign::Target.new(
        name: "crash_target",
        category: Crowbar::Campaign::TargetCategory::Security,
        expected_errors: [] of Exception.class,
        timeout: 50.milliseconds
      )
      target.add_sample("prefix_CRASH_payload_with_trailing_data")
      target.execution = ->(buf : Crowbar::Buffer) {
        str = buf.to_s
        if str.includes?("CRASH")
          raise RuntimeError.new("Simulated panic crash!")
        end
        nil
      }

      runner = Crowbar::Campaign::Runner.new(
        name: "Crash Test Runner",
        targets: [target],
        iterations_per_target: 5,
        seed: 42_u64,
        auto_shrink: true
      )

      report = runner.run
      report.clean?.should be_false
      report.total_crashes.should be > 0
      report.unique_crashes.should be >= 1

      first_crash = report.crashes.first
      first_crash.target_name.should eq("crash_target")
      first_crash.error_class.should eq("RuntimeError")
      first_crash.error_message.should contain("Simulated panic crash")
      first_crash.reproducer.to_s.should contain("CRASH")
    end

    it "emits watchdog heartbeats on schedule" do
      heartbeats = 0
      runner = Crowbar::Campaign::Runner.new(
        name: "Watchdog Test",
        iterations_per_target: 10,
        watchdog_interval: 1.millisecond
      )
      target = Crowbar::Campaign::Target.new(name: "ping_target")
      target.add_sample("hello world")
      target.execution = ->(buf : Crowbar::Buffer) { sleep 2.milliseconds; nil }
      runner.add_target(target)

      runner.on_heartbeat = ->(iters : Int32, elapsed : Float64) {
        heartbeats += 1
      }

      report = runner.run
      report.total_iterations.should eq(10)
      heartbeats.should be > 0
    end
  end

  describe Crowbar::Campaign::Battery do
    it "loads all default targets and exercises json, yaml, jwt, http, and csv" do
      targets = Crowbar::Campaign::Battery.all_targets
      targets.size.should be >= 8

      names = targets.map(&.name)
      names.should contain("json_parser")
      names.should contain("yaml_parser")
      names.should contain("jwt_validator")
      names.should contain("http_request")
      names.should contain("csv_parser")
      names.should contain("uri_parser")
      names.should contain("base64_decoder")
      names.should contain("packet_framing")

      # Test runner with small iterations across battery
      runner = Crowbar::Campaign::Runner.new(
        name: "Battery Test",
        targets: targets,
        iterations_per_target: 10,
        seed: 999_u64,
        auto_shrink: false
      )

      report = runner.run
      report.clean?.should be_true
      report.total_iterations.should eq(80)
      report.targets.size.should eq(8)
      report.total_crashes.should eq(0)
    end
  end

  describe "Two-Tier Declarative DSL: Crowbar.campaign" do
    it "configures and executes a campaign using clean declarative builder syntax" do
      report = Crowbar.campaign("Custom Declarative Campaign") do |c|
        c.iterations 15
        c.seed 777_u64
        c.auto_shrink false
        c.watchdog 5.seconds

        c.target "json_test", category: :serialization do |t|
          t.sample %({"id": 1, "test": true})
          t.rule :json
          t.expected_errors JSON::ParseException, ArgumentError
          t.execute do |buf|
            JSON.parse(buf.to_s)
          end
        end

        c.target "csv_test", category: :serialization do |t|
          t.sample "col1,col2,col3\na,b,c\n"
          t.rule :csv
          t.expected_errors CSV::MalformedCSVError, ArgumentError
          t.execute do |buf|
            CSV.parse(buf.to_s)
          end
        end
      end

      report.should be_a(Crowbar::Campaign::CampaignReport)
      report.clean?.should be_true
      report.campaign_name.should eq("Custom Declarative Campaign")
      report.total_iterations.should eq(30)
      report.targets.has_key?("json_test").should be_true
      report.targets.has_key?("csv_test").should be_true

      # Verify markdown rendering
      md = report.to_markdown
      md.should contain("# ✅ Crowbar Mutation Fuzzing Report: Custom Declarative Campaign")
      md.should contain("json_test")
      md.should contain("csv_test")
      md.should contain("Overall Throughput")

      # Verify JSON rendering
      json = report.to_json
      json.should contain("\"campaign_name\":\"Custom Declarative Campaign\"")
      json.should contain("\"total_iterations\":30")
    end
  end

  describe "CLI Campaign Command" do
    it "executes campaign via CLI App" do
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      exit_code : Int32? = nil

      app = Crowbar::CLI::App.new(
        out_io: out_io,
        err_io: err_io,
        exit_handler: ->(code : Int32) { exit_code = code; nil }
      )

      app.run(["campaign", "--iterations", "5", "--target", "json", "--quiet"])
      exit_code.should eq(0)
    end
  end
end
