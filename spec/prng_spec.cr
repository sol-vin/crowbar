require "./spec_helper"

describe Crowbar::PRNG do
  it "produces identical sequences for identical seeds" do
    prng1 = Crowbar::PRNG.new(123456789_u64)
    prng2 = Crowbar::PRNG.new(123456789_u64)

    10.times do
      prng1.next_u64.should eq(prng2.next_u64)
    end
  end

  it "reseeding restores the initial deterministic sequence" do
    prng = Crowbar::PRNG.new(42_u64)
    seq1 = (0...5).map { prng.next_u64 }

    prng.seed = 42_u64
    seq2 = (0...5).map { prng.next_u64 }

    seq1.should eq(seq2)
  end

  it "generates values within specified range" do
    prng = Crowbar::PRNG.new(99_u64)
    100.times do
      val = prng.rand(10..20)
      (val >= 10 && val <= 20).should be_true
    end
  end

  it "generates log-scale numbers correctly" do
    prng = Crowbar::PRNG.new(100_u64)
    100.times do
      val = prng.rand_log(10)
      (val >= 1 && val <= 1024).should be_true
    end
  end

  it "shuffles arrays without losing or duplicating elements" do
    prng = Crowbar::PRNG.new(101_u64)
    orig = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    shuffled = prng.shuffle(orig)

    shuffled.size.should eq(orig.size)
    shuffled.sort.should eq(orig)
  end
end
