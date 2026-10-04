require "./spec_helper"
require "../src/crowbar/evolution/bandit"

describe Crowbar::Evolution::Bandit do
  it "initializes arms and tracks pulls and rewards" do
    bandit = Crowbar::Evolution::Bandit.new
    bandit.record_pull("num")
    bandit.record_pull("num")
    bandit.reward("num", 2.0)

    bandit.pulls_for("num").should eq(2)
    bandit.rewards_for("num").should eq(2.0)
    bandit.total_pulls.should eq(2)
  end

  it "prioritizes unpulled arms for exploration" do
    bandit = Crowbar::Evolution::Bandit.new
    prng = Crowbar::PRNG.new(42_u64)

    bandit.record_pull("arm1")
    bandit.reward("arm1", 10.0)

    # arm2 has never been pulled, so UCB1 should explore arm2 first
    selected = bandit.select(["arm1", "arm2"], prng)
    selected.should eq("arm2")
  end

  it "favors higher-reward arm after both are explored" do
    bandit = Crowbar::Evolution::Bandit.new(exploration_coeff: 0.1) # low exploration to test exploitation
    prng = Crowbar::PRNG.new(42_u64)

    # Pull both arms 10 times
    10.times do
      bandit.record_pull("high_yield")
      bandit.reward("high_yield", 5.0)

      bandit.record_pull("low_yield")
      bandit.reward("low_yield", 0.1)
    end

    selected = bandit.select(["high_yield", "low_yield"], prng)
    selected.should eq("high_yield")
  end

  it "integrates with Crowbar DSL evolution block" do
    fuzzer = Crowbar.define do
      seed 12345_u64

      evolution do
        enabled true
        use_bandit true
        exploration_coeff 1.2
      end
    end

    fuzzer.pool.use_bandit.should be_true
    fuzzer.evolution.bandit.exploration_coeff.should eq(1.2)

    # Execute a transformation
    res = fuzzer.fuzz("sample data 12345")
    res.should_not be_empty

    # Report feedback to reward the last applied mutator
    fuzzer.report(res, fitness: 100.0)
    fuzzer.evolution.bandit.arms.size.should be >= 1
  end
end
