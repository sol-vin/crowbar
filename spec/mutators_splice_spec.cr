require "./spec_helper"

describe Crowbar::Mutators::Splice do
  it "has expected name and aliases" do
    mutator = Crowbar::Mutators::Splice.new
    mutator.name.should eq("splice")
    mutator.aliases.should eq(["fuse", "ft", "fn"])
    mutator.description.should contain("Markov")
  end

  it "is discoverable in MutatorPool by all aliases" do
    pool = Crowbar::MutatorPool.new
    pool.find?("splice").should_not be_nil
    pool.find?("fuse").should_not be_nil
    pool.find?("ft").should_not be_nil
    pool.find?("fn").should_not be_nil
  end

  it "performs intra-stream motif alignment and Markov jump on repeated sequences" do
    mutator = Crowbar::Mutators::Splice.new
    context = Crowbar::Context.new(42_u64)
    # A stream containing repeated motif "ABCD"
    data = "PREFIX_ABCD_MIDDLE_CONTENT_ABCD_SUFFIX"
    buffer = Crowbar::Buffer.new(data)

    success, delta = mutator.mutate(context, buffer)
    success.should be_true
    delta.should be >= 0
    buffer.to_s.should_not eq(data)
  end

  it "performs inter-sample alignment splicing when secondary samples are available" do
    mutator = Crowbar::Mutators::Splice.new
    context = Crowbar::Context.new(99_u64)
    sample_a = Crowbar::Buffer.new("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<h1>Hello</h1>")
    sample_b = Crowbar::Buffer.new("HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n\r\n{\"error\":\"missing\"}")
    context.add_sample(sample_b)

    success, delta = mutator.mutate(context, sample_a)
    success.should be_true
    sample_a.to_s.should_not eq("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<h1>Hello</h1>")
  end

  it "gracefully handles short buffers (< 4 bytes) without error" do
    mutator = Crowbar::Mutators::Splice.new
    context = Crowbar::Context.new(123_u64)
    buffer = Crowbar::Buffer.new("abc")

    success, delta = mutator.mutate(context, buffer)
    success.should be_false
    delta.should eq(-1)
  end
end
