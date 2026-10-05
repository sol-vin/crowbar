require "./spec_helper"
require "../src/crowbar/cli/app"
require "file_utils"
require "json"

def run_cli(args : Array(String), input : String = "") : Tuple(Int32, String, String)
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

describe "Crowbar CLI Application End-to-End" do
  before_each do
    FileUtils.rm_rf(".crowbar/sessions") if Dir.exists?(".crowbar/sessions")
  end

  after_each do
    FileUtils.rm_rf(".crowbar/sessions") if Dir.exists?(".crowbar/sessions")
  end

  describe "Informational and Metadata Flags" do
    it "prints version with --version and -v" do
      code, stdout, _ = run_cli(["--version"])
      code.should eq(0)
      stdout.should contain("Crowbar")
      stdout.should contain(Crowbar.version)

      code_v, stdout_v, _ = run_cli(["-v"])
      code_v.should eq(0)
      stdout_v.should contain("Crowbar")
    end

    it "prints help banner with --help and -h" do
      code, stdout, _ = run_cli(["--help"])
      code.should eq(0)
      stdout.should contain("Usage: crowbar [options]")
      stdout.should contain("crowbar session <id> next")

      code_h, stdout_h, _ = run_cli(["-h"])
      code_h.should eq(0)
      stdout_h.should contain("Usage: crowbar [options]")
    end

    it "lists all 23 structure-preserving rules, mutators, patterns, and selectors with --list" do
      code, stdout, _ = run_cli(["--list"])
      code.should eq(0)
      stdout.should contain("=== Crowbar Component Catalog ===")
      stdout.should contain("Structure-Preserving Rules (23 Formats):")

      # All 23 formats must be cataloged
      [
        "json", "yaml", "http", "dns", "csv", "xml", "url", "tlv",
        "base64", "varint", "ftp", "sql", "png", "bmp", "wav", "mp3", "wad", "pdf",
        "7z", "tar", "zip", "packet", "markdown",
      ].each do |rule|
        stdout.should contain(rule)
      end

      # Mutation patterns
      stdout.should contain("Mutation Patterns:")
      stdout.should contain("od, once")
      stdout.should contain("nd, many")
      stdout.should contain("bu, burst")

      # Mutator pool and Selectors
      stdout.should contain("Mutators (")
      stdout.should contain("Selectors & Combinators:")
    end
  end

  describe "Stream Filtering & Mutation Pipelines" do
    it "warns and exits when no input data is provided" do
      code, _, stderr = run_cli([] of String, input: "")
      code.should eq(1)
      stderr.should contain("Warning: No input data provided")
    end

    it "fuzzes input text deterministically with --seed" do
      input = "The quick brown fox jumps over the lazy dog 12345"
      code1, out1, _ = run_cli(["-s", "42"], input: input)
      code2, out2, _ = run_cli(["-s", "42"], input: input)

      code1.should eq(0)
      code2.should eq(0)
      out1.should eq(out2)
      out1.should_not eq(input)
    end

    it "renders Opal TrueColor hex diff with --diff" do
      input = "Original Buffer Content 123"
      code, stdout, _ = run_cli(["--diff", "-s", "42"], input: input)

      code.should eq(0)
      stdout.should contain("=== Crowbar Hex Diff ===")
      stdout.should contain("Original Size: 27 B")
    end

    it "applies execution patterns like burst and once" do
      input = "Some data payload to mutate with burst pattern"
      code_b, out_b, _ = run_cli(["-p", "burst", "-s", "100"], input: input)
      code_b.should eq(0)
      out_b.should_not eq(input)

      code_o, out_o, _ = run_cli(["-p", "once", "-s", "100"], input: input)
      code_o.should eq(0)
      out_o.should_not eq(input)
    end

    it "filters mutators via -m" do
      input = "1234567890"
      code, stdout, _ = run_cli(["-m", "num", "-s", "42"], input: input)
      code.should eq(0)
      stdout.should_not eq(input)
    end

    it "reads from a sample file if specified as positional argument" do
      tmp_file = "spec_sample_input.tmp"
      File.write(tmp_file, "File based input sample 999")

      begin
        code, stdout, _ = run_cli([tmp_file, "-s", "77"])
        code.should eq(0)
        stdout.should_not eq("File based input sample 999")
      ensure
        File.delete(tmp_file) if File.exists?(tmp_file)
      end
    end

    it "reports error when specified input file does not exist" do
      code, _, stderr = run_cli(["non_existent_file.xyz"])
      code.should eq(1)
      stderr.should contain("Error: File 'non_existent_file.xyz' does not exist")
    end

    it "generates multiple files with -n and -o pattern" do
      input = "Multi-file generation sample data"
      out_pattern = "spec_test_out_%n.tmp"

      code, _, _ = run_cli(["-n", "3", "-o", out_pattern, "-s", "123"], input: input)
      code.should eq(0)

      File.exists?("spec_test_out_1.tmp").should be_true
      File.exists?("spec_test_out_2.tmp").should be_true
      File.exists?("spec_test_out_3.tmp").should be_true

      # Cleanup
      (1..3).each do |i|
        File.delete("spec_test_out_#{i}.tmp") if File.exists?("spec_test_out_#{i}.tmp")
      end
    end
  end

  describe "Structure-Preserving Rule CLI Invocations" do
    it "preserves JSON AST with --rule json" do
      json_in = %({"name": "Alice", "score": 100, "active": true})
      code, stdout, _ = run_cli(["--rule", "json", "-s", "42"], input: json_in)

      code.should eq(0)
      parsed = JSON.parse(stdout)
      parsed.should be_a(JSON::Any)
    end

    it "preserves HTTP/1.x framing with --rule http" do
      http_in = "POST /api/test HTTP/1.1\r\nHost: example.com\r\nContent-Length: 5\r\n\r\nHELLO"
      code, stdout, _ = run_cli(["--rule", "http", "-s", "42"], input: http_in)

      code.should eq(0)
      stdout.should contain("\r\n\r\n")
    end

    it "preserves SQL query structure with --rule sql" do
      sql_in = "SELECT id, name FROM users WHERE age > 21"
      code, stdout, _ = run_cli(["--rule", "sql", "-s", "42"], input: sql_in)

      code.should eq(0)
      stdout.should contain("FROM users")
    end

    it "preserves FTP command framing with --rule ftp" do
      ftp_in = "USER anonymous\r\nPASS secret\r\nQUIT\r\n"
      code, stdout, _ = run_cli(["--rule", "ftp", "-s", "42"], input: ftp_in)

      code.should eq(0)
      stdout.should contain("\r\n")
    end

    it "preserves Doom WAD header framing with --rule wad" do
      wad_bytes = Bytes[
        0x49, 0x57, 0x41, 0x44,                         # IWAD
        0x01, 0x00, 0x00, 0x00,                         # 1 lump
        0x0C, 0x00, 0x00, 0x00,                         # dir at byte 12
        0x1C, 0x00, 0x00, 0x00,                         # filepos 28
        0x04, 0x00, 0x00, 0x00,                         # size 4
        0x54, 0x45, 0x53, 0x54, 0x00, 0x00, 0x00, 0x00, # "TEST\0\0\0\0"
        0xAA, 0xBB, 0xCC, 0xDD,                         # lump data
      ]
      wad_in = String.new(wad_bytes)
      code, stdout, _ = run_cli(["--rule", "wad", "-s", "42"], input: wad_in)

      code.should eq(0)
      (stdout.starts_with?("IWAD") || stdout.starts_with?("PWAD")).should be_true
    end

    it "preserves PDF header framing with --rule pdf" do
      pdf_in = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\nxref\n0 2\n0000000000 65535 f \n0000000009 00000 n \ntrailer\n<< /Size 2 /Root 1 0 R >>\nstartxref\n68\n%%EOF"
      code, stdout, _ = run_cli(["--rule", "pdf", "-s", "42"], input: pdf_in)

      code.should eq(0)
      stdout.starts_with?("%PDF-").should be_true
      stdout.ends_with?("%%EOF").should be_true
    end
  end

  describe "Stateful Session Command Workflows" do
    it "displays session help with crowbar session --help" do
      code, stdout, _ = run_cli(["session", "--help"])
      code.should eq(0)
      stdout.should contain("Crowbar Session System")
      stdout.should contain("crowbar session <id> <action>")
    end

    it "lists active sessions or reports none found" do
      code, stdout, _ = run_cli(["session", "list"])
      code.should eq(0)
      stdout.should contain("No active sessions found.")
    end

    it "fails cleanly when requesting next on a non-existent session without input" do
      code, _, stderr = run_cli(["session", "test_cli_sess", "next"], input: "")
      code.should eq(1)
      stderr.should contain("Error: Session 'test_cli_sess' does not exist.")
      stderr.should contain("Pipe initial data to start the session")
    end

    it "creates session and returns first mutant when piping baseline data into next" do
      baseline = "GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n\r\n"
      code, stdout, _ = run_cli(["session", "test_cli_sess", "next"], input: baseline)

      code.should eq(0)
      stdout.should_not be_empty
      stdout.should_not eq(baseline)

      # Session file must now exist
      Crowbar::Session.exists?("test_cli_sess").should be_true
    end

    it "generates subsequent mutant from stored session without piping" do
      # Initialize session
      baseline = "GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n\r\n"
      run_cli(["session", "test_cli_sess", "next"], input: baseline)

      # Generate second mutant without piping
      code, out2, _ = run_cli(["session", "test_cli_sess", "next"])
      code.should eq(0)
      out2.should_not be_empty

      sess = Crowbar::Session.load("test_cli_sess").not_nil!
      sess.iteration.should eq(2)
    end

    it "records reward feedback and validates inputs" do
      # Initialize session & generate mutant
      baseline = "SELECT * FROM orders WHERE status = 'shipped'"
      run_cli(["session", "test_cli_sess", "next"], input: baseline)

      # Missing reward
      code_m, _, err_m = run_cli(["session", "test_cli_sess", "reward"])
      code_m.should eq(1)
      err_m.should contain("Error: Missing reward value")

      # Invalid reward
      code_i, _, err_i = run_cli(["session", "test_cli_sess", "reward", "not_a_number"])
      code_i.should eq(1)
      err_i.should contain("Error: Invalid reward value")

      # Valid positive reward
      code_p, out_p, _ = run_cli(["session", "test_cli_sess", "reward", "0.75"])
      code_p.should eq(0)
      out_p.should contain("Recorded reward 0.75")

      sess = Crowbar::Session.load("test_cli_sess").not_nil!
      sess.last_reward.should eq(0.75)
    end

    it "displays detailed session status with bandit arm weights" do
      baseline = "Line 1\nLine 2\nLine 3\n"
      run_cli(["session", "test_cli_sess", "next"], input: baseline)
      run_cli(["session", "test_cli_sess", "reward", "0.5"])

      code, stdout, _ = run_cli(["session", "test_cli_sess", "status"])
      code.should eq(0)
      stdout.should contain("=== Crowbar Session test_cli_sess ===")
      stdout.should contain("Iteration:")
      stdout.should contain("Baseline:")
      stdout.should contain("Last Reward")
      stdout.should contain("0.5")
      stdout.should contain("Bandit Pulls:")
    end

    it "configures session via session setup subcommand" do
      baseline = "Configuration test baseline data"
      run_cli(["session", "test_cli_sess", "next"], input: baseline)

      # Display current setup
      code_s, out_s, _ = run_cli(["session", "test_cli_sess", "setup"])
      code_s.should eq(0)
      out_s.should contain("Active Rules:")

      # Add rule
      code_r, out_r, _ = run_cli(["session", "test_cli_sess", "setup", "--add-rule", "http"])
      code_r.should eq(0)
      out_r.should contain("Added rule 'http'")

      # Set mutators and pattern
      code_m, out_m, _ = run_cli(["session", "test_cli_sess", "setup", "--set-mutators", "num,bf", "-p", "burst"])
      code_m.should eq(0)
      out_m.should contain("Set mutator pool to [num, bf]")
      out_m.should contain("Set pattern to burst")

      # Add and clear scopes
      code_sc, out_sc, _ = run_cli(["session", "test_cli_sess", "setup", "--add-scope", "hdr", "--selector", "header", "--params", "length:16"])
      code_sc.should eq(0)
      out_sc.should contain("Configured scope 'hdr'")

      sess = Crowbar::Session.load("test_cli_sess").not_nil!
      sess.active_rules.should eq(["http"])
      sess.selected_mutations.should eq("num,bf")
      sess.pattern_name.should eq("burst")
      sess.scopes.size.should eq(1)

      # Clear scopes
      code_cs, out_cs, _ = run_cli(["session", "test_cli_sess", "setup", "--clear-scopes"])
      code_cs.should eq(0)
      out_cs.should contain("Cleared all scopes")

      sess_reloaded = Crowbar::Session.load("test_cli_sess").not_nil!
      sess_reloaded.scopes.should be_empty
    end

    it "lists active sessions and resets cleanly" do
      baseline = "Listing and reset baseline"
      run_cli(["session", "test_cli_sess", "next"], input: baseline)

      # Session list shows active session
      code_l, out_l, _ = run_cli(["session", "list"])
      code_l.should eq(0)
      out_l.should contain("test_cli_sess")

      # Reset session
      code_r, out_r, _ = run_cli(["session", "test_cli_sess", "reset"])
      code_r.should eq(0)
      out_r.should contain("has been reset")

      # Session list now reports empty
      code_l2, out_l2, _ = run_cli(["session", "list"])
      code_l2.should eq(0)
      out_l2.should contain("No active sessions found.")
    end

    it "auto-resets session baseline when piping new different data" do
      baseline1 = "First baseline payload"
      run_cli(["session", "test_cli_sess", "next"], input: baseline1)

      sess1 = Crowbar::Session.load("test_cli_sess").not_nil!
      sess1.baseline.to_s.should eq(baseline1)
      sess1.iteration.should eq(1)

      # Pipe new baseline
      baseline2 = "Completely different second baseline payload"
      run_cli(["session", "test_cli_sess", "next"], input: baseline2)

      sess2 = Crowbar::Session.load("test_cli_sess").not_nil!
      sess2.baseline.to_s.should eq(baseline2)
      sess2.iteration.should eq(1)
    end
  end
end
