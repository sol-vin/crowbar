require "./spec_helper"
require "../src/crowbar/cli/app"
require "file_utils"
require "json"

def run_session_cli(args : Array(String), input : String = "") : Tuple(Int32, String, String)
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

describe "Crowbar Session Full Lifecycle & Error Handling" do
  test_dir = File.join(Dir.tempdir, "crowbar_sess_lifecycle_#{Random.rand(10000)}")

  before_each do
    FileUtils.mkdir_p(test_dir)
    ENV["CROWBAR_SESSION_DIR"] = test_dir
  end

  after_each do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
    ENV.delete("CROWBAR_SESSION_DIR")
  end

  after_all do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
    ENV.delete("CROWBAR_SESSION_DIR")
  end

  describe "Session Syntax Variants (session <id> setup vs session setup <id>)" do
    it "supports configuring session using 'crowbar session setup <id>'" do
      # 1. Initialize session
      run_session_cli(["session", "setup_order_test", "next"], input: "Initial session payload")

      # 2. Setup using prefix syntax: session setup <id> [options]
      code, out, _ = run_session_cli(["session", "setup", "setup_order_test", "--add-rule", "http", "--template", "PREFIX[%f]"])
      code.should eq(0)
      out.should contain("Added rule 'http'")
      out.should contain("Set template to 'PREFIX[%f]'")

      sess = Crowbar::Session.load("setup_order_test").not_nil!
      sess.active_rules.should contain("http")
      sess.template.should eq("PREFIX[%f]")
    end

    it "reports clean error when session ID is missing in 'crowbar session setup'" do
      code, _, stderr = run_session_cli(["session", "setup"])
      code.should eq(1)
      stderr.should contain("Error: Missing session ID. Usage: crowbar session setup <id> [options]")
    end
  end

  describe "Scope Management via session setup" do
    it "configures all selector types (range, header, footer, field, chars, stride, entropy, regex)" do
      sess_id = "scopes_test"
      run_session_cli(["session", sess_id, "next"], input: "HeaderBytes1234,col1,col2,col3,FOOTER")

      # 1. Header & Footer scopes
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_hdr", "--selector", "header", "--params", "length:8", "-w", "2.0"])
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_ftr", "--selector", "footer", "--params", "length:6"])

      # 2. Field & Chars scopes
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_fld", "--selector", "field", "--params", "delimiter:,,index:1"])
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_chr", "--selector", "chars", "--params", "kind:digits"])

      # 3. Stride & Entropy scopes
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_str", "--selector", "stride", "--params", "step:4,offset:0,length:1"])
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_ent", "--selector", "entropy", "--params", "mode:high"])

      # 4. Regex & ByteRange scopes
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_rgx", "--selector", "regex", "--params", "pattern:[a-z]+"])
      run_session_cli(["session", sess_id, "setup", "--add-scope", "s_rng", "--selector", "range", "--params", "start:2,end:10"])

      sess = Crowbar::Session.load(sess_id).not_nil!
      sess.scopes.size.should eq(8)

      # 5. Remove single scope
      code_rm, out_rm, _ = run_session_cli(["session", sess_id, "setup", "--remove-scope", "s_ftr"])
      code_rm.should eq(0)
      out_rm.should contain("Removed scope 's_ftr'")

      sess_after_rm = Crowbar::Session.load(sess_id).not_nil!
      sess_after_rm.scopes.size.should eq(7)
      sess_after_rm.scopes.any? { |s| s.name == "s_ftr" }.should be_false

      # 6. Clear all scopes
      code_cl, out_cl, _ = run_session_cli(["session", sess_id, "setup", "--clear-scopes"])
      code_cl.should eq(0)
      out_cl.should contain("Cleared all scopes")

      sess_cleared = Crowbar::Session.load(sess_id).not_nil!
      sess_cleared.scopes.should be_empty
    end
  end

  describe "Multi-Rule and Mutator Lifecycle" do
    it "adds, removes, and clears multiple active rules" do
      sess_id = "rules_test"
      run_session_cli(["session", sess_id, "next"], input: "Dummy baseline")

      # Add multiple rules
      run_session_cli(["session", sess_id, "setup", "--add-rule", "mp3"])
      run_session_cli(["session", sess_id, "setup", "--add-rule", "wav"])

      sess = Crowbar::Session.load(sess_id).not_nil!
      sess.active_rules.should eq(["mp3", "wav"])

      # Remove one rule
      run_session_cli(["session", sess_id, "setup", "--remove-rule", "mp3"])
      sess2 = Crowbar::Session.load(sess_id).not_nil!
      sess2.active_rules.should eq(["wav"])

      # Clear rules
      run_session_cli(["session", sess_id, "setup", "--clear-rules"])
      sess3 = Crowbar::Session.load(sess_id).not_nil!
      sess3.active_rules.should be_empty
    end

    it "adds, removes, and resets mutators" do
      sess_id = "mutators_test"
      run_session_cli(["session", sess_id, "next"], input: "Mutator pool test")

      # Add mutators
      run_session_cli(["session", sess_id, "setup", "--add-mutator", "sec"])
      run_session_cli(["session", sess_id, "setup", "--add-mutator", "fuse"])

      sess = Crowbar::Session.load(sess_id).not_nil!
      sess.selected_mutations.should eq("sec,fuse")

      # Remove mutator
      run_session_cli(["session", sess_id, "setup", "--remove-mutator", "sec"])
      sess2 = Crowbar::Session.load(sess_id).not_nil!
      sess2.selected_mutations.should eq("fuse")

      # Reset mutators to default
      run_session_cli(["session", sess_id, "setup", "--reset-mutators"])
      sess3 = Crowbar::Session.load(sess_id).not_nil!
      sess3.selected_mutations.should be_nil
    end

    it "configures and clears template, uniqueness, and seek offset" do
      sess_id = "features_test"
      run_session_cli(["session", sess_id, "next"], input: "Features test payload")

      # Configure template, unique with capacity, and seek
      run_session_cli(["session", sess_id, "setup", "--template", "WRAP[%f]", "--unique", "-C", "3000", "-S", "42"])

      sess = Crowbar::Session.load(sess_id).not_nil!
      sess.template.should eq("WRAP[%f]")
      sess.unique_enabled.should be_true
      sess.uniqueness_capacity.should eq(3000)
      sess.seek_offset.should eq(42)

      # Disable unique and remove template
      run_session_cli(["session", sess_id, "setup", "--remove-template", "--no-unique", "--clear-checksums"])

      sess2 = Crowbar::Session.load(sess_id).not_nil!
      sess2.template.should be_nil
      sess2.unique_enabled.should be_false
      sess2.seen_hashes.should be_empty
    end
  end

  describe "Evolutionary Feedback & Corpus Integration" do
    it "elevates high-reward mutants into evolutionary corpus candidates" do
      sess_id = "evo_test"
      run_session_cli(["session", sess_id, "next"], input: "Evolutionary corpus baseline")

      # Generate mutant and reward with high positive fitness
      run_session_cli(["session", sess_id, "reward", "0.95"])

      sess = Crowbar::Session.load(sess_id).not_nil!
      sess.corpus_items.size.should eq(1)
      sess.corpus_items.first.fitness.should eq(0.95)

      # Subsequent next builds engine with candidate in corpus
      code, out, _ = run_session_cli(["session", sess_id, "next"])
      code.should eq(0)
      out.should_not be_empty
    end

    it "prunes candidate from corpus when negative reward is given" do
      sess_id = "prune_test"
      run_session_cli(["session", sess_id, "next"], input: "Negative reward pruning test")
      run_session_cli(["session", sess_id, "reward", "0.8"])

      sess1 = Crowbar::Session.load(sess_id).not_nil!
      sess1.corpus_items.size.should eq(1)

      # Now give negative reward to current mutant
      run_session_cli(["session", sess_id, "reward", "-0.5"])
      sess2 = Crowbar::Session.load(sess_id).not_nil!
      sess2.corpus_items.size.should eq(0)
    end
  end

  describe "Session Show Command & Errors" do
    it "supports short aliases -b and -m for show" do
      sess_id = "show_aliases_test"
      baseline = "GET /resource HTTP/1.1\r\n\r\n"
      run_session_cli(["session", sess_id, "next"], input: baseline)

      code_b, out_b, _ = run_session_cli(["session", sess_id, "show", "-b"])
      code_b.should eq(0)
      out_b.should eq(baseline)

      code_m, out_m, _ = run_session_cli(["session", sess_id, "show", "-m"])
      code_m.should eq(0)
      out_m.should_not be_empty
    end

    it "reports error when attempting to show non-existent session" do
      code, _, stderr = run_session_cli(["session", "ghost_session", "show"])
      code.should eq(1)
      stderr.should contain("Error: Session 'ghost_session' does not exist.")
    end

    it "reports error for invalid show target" do
      sess_id = "show_target_err"
      run_session_cli(["session", sess_id, "next"], input: "Hello")

      code, _, stderr = run_session_cli(["session", sess_id, "show", "--invalid-flag"])
      code.should eq(1)
      stderr.should contain("Unknown show target '--invalid-flag'")
    end
  end

  describe "Error Scenarios & Exit Codes" do
    it "fails with exit code 1 when session action is unknown" do
      code, _, stderr = run_session_cli(["session", "my_sess", "unknown_action"])
      code.should eq(1)
      stderr.should contain("Unknown session action: 'unknown_action'")
    end

    it "fails with exit code 1 when action is missing" do
      code, _, stderr = run_session_cli(["session", "my_sess"])
      code.should eq(1)
      stderr.should contain("Error: Missing action for session 'my_sess'")
    end

    it "fails when reward is requested before generating any mutant" do
      sess_id = "no_mutant_reward"
      # Create empty session manually
      Crowbar::Session.load_or_create(sess_id, Crowbar::Buffer.new("dummy"))

      code, _, stderr = run_session_cli(["session", sess_id, "reward", "0.5"])
      code.should eq(1)
      stderr.should contain("has not generated any items yet")
    end

    it "handles reset on non-existent session gracefully" do
      code, _, stderr = run_session_cli(["session", "nonexistent_reset", "reset"])
      code.should eq(0)
      stderr.should contain("Session 'nonexistent_reset' does not exist")
    end
  end
end
