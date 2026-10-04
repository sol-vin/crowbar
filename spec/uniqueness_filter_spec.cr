require "./spec_helper"

describe Crowbar::Evolution::UniquenessFilter do
  it "computes deterministic 64-bit FNV-1a digests" do
    buf1 = Crowbar::Buffer.new("hello world")
    buf2 = Crowbar::Buffer.new("hello world")
    buf3 = Crowbar::Buffer.new("hello world!")

    h1 = Crowbar::Evolution::UniquenessFilter.hash_buffer(buf1)
    h2 = Crowbar::Evolution::UniquenessFilter.hash_buffer(buf2)
    h3 = Crowbar::Evolution::UniquenessFilter.hash_buffer(buf3)

    h1.should eq(h2)
    h1.should_not eq(h3)
  end

  it "filters duplicate inputs and accepts unique inputs" do
    filter = Crowbar::Evolution::UniquenessFilter.new(capacity: 100)
    buf_a = Crowbar::Buffer.new("mutant_1")
    buf_b = Crowbar::Buffer.new("mutant_2")

    filter.filter(buf_a).should be_true
    filter.filter(buf_a).should be_false # Already seen!
    filter.filter(buf_b).should be_true
    filter.size.should eq(2)
  end

  it "evicts oldest entries when reaching capacity limit" do
    filter = Crowbar::Evolution::UniquenessFilter.new(capacity: 3)
    filter.filter(Crowbar::Buffer.new("item1")).should be_true
    filter.filter(Crowbar::Buffer.new("item2")).should be_true
    filter.filter(Crowbar::Buffer.new("item3")).should be_true
    filter.size.should eq(3)

    # Adding 4th item should evict item1
    filter.filter(Crowbar::Buffer.new("item4")).should be_true
    filter.size.should eq(3)
    filter.seen?(Crowbar::Buffer.new("item1")).should be_false
    filter.seen?(Crowbar::Buffer.new("item2")).should be_true
    filter.seen?(Crowbar::Buffer.new("item3")).should be_true
    filter.seen?(Crowbar::Buffer.new("item4")).should be_true
  end

  it "serializes and restores hash history" do
    filter = Crowbar::Evolution::UniquenessFilter.new(capacity: 10)
    filter.add(Crowbar::Buffer.new("alpha"))
    filter.add(Crowbar::Buffer.new("beta"))
    hashes = filter.to_a
    hashes.size.should eq(2)

    new_filter = Crowbar::Evolution::UniquenessFilter.new(capacity: 10)
    new_filter.load_hashes(hashes)
    new_filter.seen?(Crowbar::Buffer.new("alpha")).should be_true
    new_filter.seen?(Crowbar::Buffer.new("beta")).should be_true
    new_filter.seen?(Crowbar::Buffer.new("gamma")).should be_false
  end
end
