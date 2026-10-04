require "./spec_helper"
require "file_utils"

describe Crowbar::Session do
  test_dir = ".crowbar/test_sessions"

  before_each do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
  end

  after_each do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
  end

  it "creates and persists a new session" do
    baseline = Crowbar::Buffer.new("Hello, World!")
    session = Crowbar::Session.load_or_create("test_1", baseline, seed: 1234_u64, dir: test_dir)

    session.id.should eq("test_1")
    session.iteration.should eq(0)
    session.baseline.to_s.should eq("Hello, World!")
    Crowbar::Session.exists?("test_1", dir: test_dir).should be_true

    loaded = Crowbar::Session.load("test_1", dir: test_dir)
    loaded.should_not be_nil
    loaded.not_nil!.baseline.to_s.should eq("Hello, World!")
  end

  it "generates sequential mutants and tracks mutators applied" do
    baseline = Crowbar::Buffer.new("POST /api/v1 HTTP/1.1\r\nHost: example.com\r\n\r\n")
    session = Crowbar::Session.load_or_create("seq_test", baseline, rule_name: "http", seed: 42_u64, dir: test_dir)

    # First mutant
    mutant1 = session.next_mutant(dir: test_dir)
    session.iteration.should eq(1)
    session.last_mutant.should_not be_nil
    session.last_mutators.should_not be_empty

    # Second mutant
    mutant2 = session.next_mutant(dir: test_dir)
    session.iteration.should eq(2)

    # Verify history
    session.history.size.should eq(2)
    session.history[0].action.should eq("next")
    session.history[1].action.should eq("next")

    # Reload from disk and verify persistence
    reloaded = Crowbar::Session.load("seq_test", dir: test_dir).not_nil!
    reloaded.iteration.should eq(2)
    reloaded.history.size.should eq(2)
  end

  it "credits bandit mutators and updates corpus on positive reward" do
    baseline = Crowbar::Buffer.new("Sample text to mutate")
    session = Crowbar::Session.load_or_create("reward_pos", baseline, seed: 99_u64, dir: test_dir)

    session.next_mutant(dir: test_dir)
    last_muts = session.last_mutators.dup
    last_muts.should_not be_empty

    session.reward(0.8, dir: test_dir)
    session.last_reward.should eq(0.8)

    # Verify bandit arm rewards
    last_muts.each do |m|
      session.arms[m]?.should_not be_nil
      session.arms[m].rewards.should be >= 0.8
    end

    # Verify corpus contains candidate
    session.corpus_items.size.should eq(1)
    session.corpus_items.first.fitness.should eq(0.8)

    # Reload and verify
    reloaded = Crowbar::Session.load("reward_pos", dir: test_dir).not_nil!
    reloaded.last_reward.should eq(0.8)
    reloaded.corpus_items.size.should eq(1)
  end

  it "penalizes bandit mutators and prunes candidate on negative reward" do
    baseline = Crowbar::Buffer.new("Sample text to mutate")
    session = Crowbar::Session.load_or_create("reward_neg", baseline, seed: 101_u64, dir: test_dir)

    session.next_mutant(dir: test_dir)
    last_muts = session.last_mutators.dup

    session.reward(-0.5, dir: test_dir)
    session.last_reward.should eq(-0.5)

    last_muts.each do |m|
      session.arms[m]?.should_not be_nil
      session.arms[m].rewards.should eq(-0.5)
    end

    # Corpus should not contain candidate
    session.corpus_items.empty?.should be_true
  end

  it "auto-resets when new baseline input text is provided" do
    baseline1 = Crowbar::Buffer.new("First baseline input")
    session = Crowbar::Session.load_or_create("reset_auto", baseline1, seed: 777_u64, dir: test_dir)

    session.next_mutant(dir: test_dir)
    session.iteration.should eq(1)
    session.corpus_items << Crowbar::CandidateState.new("dummy", 1.0, 1_i64, ["bd"])

    # Load with completely different input
    baseline2 = Crowbar::Buffer.new("Second completely new input text")
    session2 = Crowbar::Session.load_or_create("reset_auto", baseline2, seed: 777_u64, dir: test_dir)

    session2.iteration.should eq(0)
    session2.baseline.to_s.should eq("Second completely new input text")
    session2.corpus_items.empty?.should be_true
    session2.history.last.action.should eq("reset")
  end

  it "explicitly resets a session" do
    baseline = Crowbar::Buffer.new("To be deleted")
    Crowbar::Session.load_or_create("to_delete", baseline, dir: test_dir)
    Crowbar::Session.exists?("to_delete", dir: test_dir).should be_true

    Crowbar::Session.reset("to_delete", dir: test_dir).should be_true
    Crowbar::Session.exists?("to_delete", dir: test_dir).should be_false
  end

  it "lists all active sessions" do
    Crowbar::Session.load_or_create("sess_a", Crowbar::Buffer.new("A"), dir: test_dir)
    Crowbar::Session.load_or_create("sess_b", Crowbar::Buffer.new("B"), dir: test_dir)

    list = Crowbar::Session.list(dir: test_dir)
    list.should contain("sess_a")
    list.should contain("sess_b")
  end
end
