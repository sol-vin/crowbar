require "./spec_helper"

describe "Crowbar Evolutionary Engine" do
  it "manages population capacity and sorts candidates descending by fitness" do
    corpus = Crowbar::Evolution::Corpus.new(max_size: 3)
    corpus.add(Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("low"), fitness: 1.0))
    corpus.add(Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("high"), fitness: 10.0))
    corpus.add(Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("mid"), fitness: 5.0))
    corpus.add(Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("highest"), fitness: 20.0))

    corpus.size.should eq(3)                     # Max capacity respected
    corpus.best.not_nil!.fitness.should eq(20.0) # Highest on top
  end

  it "tournament selection picks high-fitness candidates" do
    prng = Crowbar::PRNG.new(42_u64)
    corpus = Crowbar::Evolution::Corpus.new(max_size: 10)
    corpus.add(Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("A"), fitness: 1.0))
    corpus.add(Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("B"), fitness: 2.0))
    corpus.add(Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("C"), fitness: 50.0))

    selected = corpus.tournament_select(prng, k: 3)
    selected.not_nil!.fitness.should be >= 2.0
  end

  it "crossover splices two parents into a hybrid offspring" do
    prng = Crowbar::PRNG.new(42_u64)
    p1 = Crowbar::Buffer.new("AAAA")
    p2 = Crowbar::Buffer.new("BBBB")

    child = Crowbar::Evolution::Crossover.recombine(p1, p2, prng)
    child.size.should be >= 2
  end

  it "hones in on high-fitness traits via feedback reporting" do
    fuzzer = Crowbar.define do
      seed 123_u64
      evolution do
        enabled true
        population_size 16
        exploration_rate 0.0 # Force evolutionary selection
      end
    end

    sample = "target_search"

    30.times do
      candidate = fuzzer.fuzz(sample)
      # Reward candidates that contain 'X' or have longer size
      score = candidate.to_s.count('A').to_f64 * 10.0 + candidate.size
      fuzzer.report(candidate, fitness: score)
    end

    fuzzer.evolution.corpus.best.not_nil!.fitness.should be > 13.0
  end

  it "triggers novelty culling upon reaching stagnation limit" do
    manager = Crowbar::Evolution::Manager.new(population_size: 10)
    manager.stagnation_limit = 5

    # Report same or lower fitness repeatedly
    10.times do
      manager.report("test", fitness: 5.0)
    end

    # Stagnation counter should reset after culling
    manager.stagnation_count.should be < 5
  end
end
