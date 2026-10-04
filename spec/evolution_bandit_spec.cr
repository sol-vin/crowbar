require "./spec_helper"
require "file_utils"

describe Crowbar::Evolution::Bandit do
  it "prioritizes unpulled arms before exploiting tested arms" do
    bandit = Crowbar::Evolution::Bandit.new
    prng = Crowbar::PRNG.new(42_u64)
    arms = ["bd", "bf", "num"]

    selected = Set(String).new
    3.times do
      arm = bandit.select(arms, prng)
      selected << arm
      bandit.record_pull(arm)
    end

    # All 3 arms must have been explored once before any duplicate
    selected.size.should eq(3)
    bandit.total_pulls.should eq(3)
  end

  it "converges toward the high-reward arm over multi-round trials" do
    bandit = Crowbar::Evolution::Bandit.new(exploration_coeff: 0.5)
    prng = Crowbar::PRNG.new(12345_u64)
    arms = ["arm_good", "arm_bad1", "arm_bad2", "arm_bad3"]

    pull_counts = Hash(String, Int32).new(0)

    # Run 100 trials
    100.times do
      chosen = bandit.select(arms, prng)
      bandit.record_pull(chosen)
      pull_counts[chosen] += 1

      if chosen == "arm_good"
        bandit.reward(chosen, 1.0)
      else
        bandit.reward(chosen, -0.5)
      end
    end

    # arm_good should dominate total pulls
    pull_counts["arm_good"].should be > pull_counts["arm_bad1"]
    pull_counts["arm_good"].should be > pull_counts["arm_bad2"]
    pull_counts["arm_good"].should be > pull_counts["arm_bad3"]
    pull_counts["arm_good"].should be >= 50
  end

  it "persists and updates bandit arm statistics across session calls" do
    test_dir = ".crowbar/test_bandit_sessions"
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)

    begin
      baseline = Crowbar::Buffer.new("Test payload data")
      session = Crowbar::Session.load_or_create("bandit_test", baseline, seed: 99_u64, dir: test_dir)

      # Generate 3 mutants and reward them
      3.times do |i|
        session.next_mutant(dir: test_dir)
        session.reward((i + 1) * 0.25, dir: test_dir)
      end

      # Reload session from disk
      loaded = Crowbar::Session.load("bandit_test", dir: test_dir).not_nil!
      loaded.arms.should_not be_empty
      loaded.total_pulls.should be >= 3

      # Verify bandit arms have recorded rewards
      total_recorded = loaded.arms.values.sum(&.rewards)
      total_recorded.should be > 0.0
    ensure
      FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
    end
  end
end
