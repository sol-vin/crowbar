require "./spec_helper"
require "../src/crowbar/cli/app"
require "file_utils"
require "json"

def run_ext_cli(args : Array(String), input : String = "") : Tuple(Int32, String, String)
  in_io = IO::Memory.new(input)
  out_io = IO::Memory.new
  err_io = IO::Memory.new

  exit_code = 0
  app = Crowbar::CLI::App.new(
    in_io: in_io,
    out_io: out_io,
    err_io: err_io,
    exit_handler: ->(code : Int32) {
      exit_code = code
      raise Crowbar::CLI::ExitException.new(code)
    }
  )

  begin
    app.run(args)
  rescue ex : Crowbar::CLI::ExitException
    # Captured exit code
  end

  {exit_code, out_io.to_s, err_io.to_s}
end

describe "Crowbar Extended CLI Features & JSON Modes" do
  before_each do
    FileUtils.rm_rf(".crowbar/sessions") if Dir.exists?(".crowbar/sessions")
  end

  after_each do
    FileUtils.rm_rf(".crowbar/sessions") if Dir.exists?(".crowbar/sessions")
  end

  describe "Machine-readable JSON Listings" do
    it "emits valid JSON for crowbar --list --json" do
      code, stdout, _ = run_ext_cli(["--list", "--json"])
      code.should eq(0)

      parsed = JSON.parse(stdout)
      parsed["rules"].as_a.size.should be >= 18
      parsed["patterns"].as_a.size.should be >= 3
      parsed["mutators"].as_a.size.should be >= 30
    end

    it "emits valid JSON for crowbar --list-rules --json" do
      code, stdout, _ = run_ext_cli(["--list-rules", "--json"])
      code.should eq(0)

      parsed = JSON.parse(stdout)
      parsed.as_a.size.should be >= 18
      parsed.as_a.any? { |r| r["name"] == "http" }.should be_true
      parsed.as_a.any? { |r| r["name"] == "mp3" }.should be_true
    end

    it "emits valid JSON for crowbar --list-mutators --json" do
      code, stdout, _ = run_ext_cli(["--list-mutators", "--json"])
      code.should eq(0)

      parsed = JSON.parse(stdout)
      parsed.as_a.size.should be >= 30
      parsed.as_a.any? { |m| m["name"] == "bf" }.should be_true
    end
  end

  describe "Format Alias and Pipeline Auto-Detection" do
    it "supports -f as an alias for --rule" do
      http_in = "GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n"
      code, stdout, _ = run_ext_cli(["-f", "http", "-s", "42"], input: http_in)
      code.should eq(0)
      stdout.should contain("\r\n\r\n")
      stdout.should_not eq(http_in)
    end

    it "supports --format as an alias for --rule" do
      dns_bytes = Bytes[
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x07, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 0x03, 0x63, 0x6F, 0x6D, 0x00,
        0x00, 0x01, 0x00, 0x01,
      ]
      code, stdout, _ = run_ext_cli(["--format", "dns", "-s", "42"], input: String.new(dns_bytes))
      code.should eq(0)
      stdout.size.should be >= 12
    end

    it "auto-detects format in pipeline with --auto flag" do
      png_bytes = Bytes[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
      ]
      code, stdout, _ = run_ext_cli(["--auto", "-s", "42"], input: String.new(png_bytes))
      code.should eq(0)
      stdout.starts_with?("\x89PNG\r\n\x1a\n").should be_true
    end
  end

  describe "Extended Session Commands: show, history & JSON" do
    it "shows session baseline and latest mutant with show command" do
      baseline = "GET /user HTTP/1.1\r\nHost: example.com\r\n\r\n"
      run_ext_cli(["session", "ext_sess", "next"], input: baseline)

      # Show baseline
      code_b, out_b, _ = run_ext_cli(["session", "ext_sess", "show", "--baseline"])
      code_b.should eq(0)
      out_b.should eq(baseline)

      # Show mutant
      code_m, out_m, _ = run_ext_cli(["session", "ext_sess", "show", "--mutant"])
      code_m.should eq(0)
      out_m.should_not be_empty
      out_m.should_not eq(baseline)
    end

    it "displays and limits event history timeline" do
      baseline = "Sample text for history"
      run_ext_cli(["session", "ext_sess", "next"], input: baseline)
      run_ext_cli(["session", "ext_sess", "reward", "0.5"])
      run_ext_cli(["session", "ext_sess", "next"])
      run_ext_cli(["session", "ext_sess", "reward", "-0.2"])

      # Text history
      code_h, out_h, _ = run_ext_cli(["session", "ext_sess", "history"])
      code_h.should eq(0)
      out_h.should contain("History for Session ext_sess")
      out_h.should contain("next")
      out_h.should contain("reward")

      # JSON history
      code_j, out_j, _ = run_ext_cli(["session", "ext_sess", "history", "--json"])
      code_j.should eq(0)
      entries = JSON.parse(out_j).as_a
      entries.size.should be >= 4
    end

    it "emits valid JSON for session status and session list" do
      baseline = "POST /submit HTTP/1.1\r\nHost: api.test\r\n\r\n"
      run_ext_cli(["session", "ext_sess", "next"], input: baseline)
      run_ext_cli(["session", "ext_sess", "reward", "0.9"])

      # Status JSON
      code_s, out_s, _ = run_ext_cli(["session", "ext_sess", "status", "--json"])
      code_s.should eq(0)
      status_data = JSON.parse(out_s)
      status_data["id"].as_s.should eq("ext_sess")
      status_data["iteration"].as_i.should eq(1)
      status_data["last_reward"].as_f.should eq(0.9)
      status_data["arms"].as_a.should_not be_empty

      # List JSON
      code_l, out_l, _ = run_ext_cli(["session", "list", "--json"])
      code_l.should eq(0)
      list_data = JSON.parse(out_l).as_a
      list_data.size.should eq(1)
      list_data.first["id"].as_s.should eq("ext_sess")
    end
  end
end
