require "./spec_helper"
require "../src/crowbar"
require "../src/crowbar/cli/app"
require "file_utils"
require "json"

def run_reward_replay_cli(args : Array(String), input : String = "") : Tuple(Int32, String, String)
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
  end

  {exit_code, out_io.to_s, err_io.to_s}
end

describe "Session Deferred Rewarding, Item Tracking & Deterministic Replay" do
  test_dir = File.join(Dir.tempdir, "crowbar_reward_replay_#{Random.rand(10000)}")

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

  it "records SessionItem records with transformation steps during next_mutant" do
    baseline = Crowbar::Buffer.new("Initial session baseline buffer")
    sess = Crowbar::Session.new("trace_sess", baseline)
    sess.save(test_dir)

    3.times do
      sess.next_mutant(dir: test_dir)
    end

    sess.items.size.should eq(3)
    sess.items.each_with_index do |item, idx|
      item.iteration.should eq(idx + 1)
      item.size.should be > 0
      item.steps.size.should be > 0
      item.seed.should be > 0_u64
      item.reward.should be_nil
    end
  end

  it "allows rewarding past iterations and credits the respective mutators" do
    sess_id = "deferred_reward_sess"

    # 1. Generate 4 iterations via CLI
    code1, _, _ = run_reward_replay_cli(["session", sess_id, "next", "-m", "bf"], input: "Sample baseline text 1234567890")
    code1.should eq(0)
    code2, _, _ = run_reward_replay_cli(["session", sess_id, "next", "-m", "sec"])
    code2.should eq(0)
    code3, _, _ = run_reward_replay_cli(["session", sess_id, "next", "-m", "splice"])
    code3.should eq(0)
    code4, _, _ = run_reward_replay_cli(["session", sess_id, "next", "-m", "nest"])
    code4.should eq(0)

    # 2. Reward iteration #2 (which ran 'sec') with +1.0
    code_rwd, out_rwd, _ = run_reward_replay_cli(["session", sess_id, "reward", "1.0", "-i", "2"])
    code_rwd.should eq(0)
    out_rwd.should contain("iteration #2")

    # 3. Reload session and verify bandit arm credit and corpus promotion
    sess = Crowbar::Session.load(sess_id).not_nil!
    item2 = sess.get_item(2).not_nil!
    item2.reward.should eq(1.0)
    sess.arms["sec"]?.should_not be_nil
    sess.arms["sec"].rewards.should eq(1.0)

    # Iteration 2 mutant must now be in the evolutionary corpus
    sess.corpus_items.size.should be >= 1
    sess.corpus_items.any? { |c| c.generation == 2 }.should be_true
  end

  it "retrieves past mutants by numeric index with show command" do
    sess_id = "show_numeric_sess"

    run_reward_replay_cli(["session", sess_id, "next", "-s", "100"], input: "Baseline alpha beta gamma")
    run_reward_replay_cli(["session", sess_id, "next", "-s", "200"])
    run_reward_replay_cli(["session", sess_id, "next", "-s", "300"])

    code, out, _ = run_reward_replay_cli(["session", sess_id, "show", "2"])
    code.should eq(0)
    out.size.should be > 0

    sess = Crowbar::Session.load(sess_id).not_nil!
    expected_buf = sess.get_mutant(2).not_nil!
    out.should eq(expected_buf.to_s)
  end

  it "replays past iterations deterministically and outputs transformation breakdown" do
    sess_id = "replay_sess"

    run_reward_replay_cli(["session", sess_id, "next", "-s", "42", "-m", "bf,sec"], input: "Deterministic replay test buffer")
    run_reward_replay_cli(["session", sess_id, "next", "-s", "43", "-m", "splice,pad"])

    # Replay iteration 1 in text breakdown mode
    code_rep, out_rep, _ = run_reward_replay_cli(["session", sess_id, "replay", "1"])
    code_rep.should eq(0)
    out_rep.should contain("Replayed Iteration #1")
    out_rep.should contain("Transformation Process Tree:")

    # Replay iteration 1 in JSON mode
    code_json, out_json, _ = run_reward_replay_cli(["session", sess_id, "replay", "1", "--json"])
    code_json.should eq(0)
    parsed = JSON.parse(out_json)
    parsed["iteration"].as_i.should eq(1)
    parsed["steps"].as_a.size.should be > 0

    # Replay to output file
    out_file = File.join(test_dir, "replayed_iter1.bin")
    code_out, _, _ = run_reward_replay_cli(["session", sess_id, "replay", "1", "-o", out_file])
    code_out.should eq(0)
    File.exists?(out_file).should be_true
    File.size(out_file).should be > 0
  end
end
