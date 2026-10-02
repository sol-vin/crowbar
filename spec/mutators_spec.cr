require "./spec_helper"

describe "Crowbar Mutators" do
  it "ByteDrop removes a byte" do
    ctx = Crowbar::Context.new(42_u64)
    buf = Crowbar::Buffer.new("ABCDEFG")
    mutator = Crowbar::Mutators::ByteDrop.new

    success, delta = mutator.mutate(ctx, buf)
    success.should be_true
    buf.size.should eq(6)
  end

  it "ByteFlip inverts bits" do
    ctx = Crowbar::Context.new(42_u64)
    buf = Crowbar::Buffer.new("AAAAAA")
    mutator = Crowbar::Mutators::ByteFlip.new

    success, _ = mutator.mutate(ctx, buf)
    success.should be_true
    buf.to_s.should_not eq("AAAAAA")
  end

  it "ByteInsert increases buffer size" do
    ctx = Crowbar::Context.new(42_u64)
    buf = Crowbar::Buffer.new("12345")
    mutator = Crowbar::Mutators::ByteInsert.new

    success, _ = mutator.mutate(ctx, buf)
    success.should be_true
    buf.size.should eq(6)
  end

  it "SequenceRepeat stutters a sub-slice" do
    ctx = Crowbar::Context.new(42_u64)
    buf = Crowbar::Buffer.new("HELLO_WORLD_TESTING")
    mutator = Crowbar::Mutators::SequenceRepeat.new

    success, _ = mutator.mutate(ctx, buf)
    success.should be_true
    buf.size.should be > 19
  end

  it "LineDelete removes a line in multiline text" do
    ctx = Crowbar::Context.new(42_u64)
    buf = Crowbar::Buffer.new("line 1\nline 2\nline 3\n")
    mutator = Crowbar::Mutators::LineDelete.new

    success, delta = mutator.mutate(ctx, buf)
    success.should be_true
    delta.should be > 0 # Positive feedback for finding lines
    buf.lines.size.should eq(2)
  end

  it "TreeDelete removes a balanced delimiter block" do
    ctx = Crowbar::Context.new(42_u64)
    buf = Crowbar::Buffer.new("start [target_to_remove] finish")
    mutator = Crowbar::Mutators::TreeDelete.new

    success, delta = mutator.mutate(ctx, buf)
    success.should be_true
    delta.should be > 0
    buf.to_s.should_not contain("target_to_remove")
  end

  it "BoundaryNumbers transforms integers to edge cases" do
    ctx = Crowbar::Context.new(42_u64)
    buf = Crowbar::Buffer.new("item_count = 50;")
    mutator = Crowbar::Mutators::BoundaryNumbers.new

    success, delta = mutator.mutate(ctx, buf)
    success.should be_true
    delta.should eq(2) # Strong positive feedback
    buf.to_s.should_not eq("item_count = 50;")
  end

  it "adjusts adaptive scores within [2, 10]" do
    mutator = Crowbar::Mutators::ByteDrop.new
    mutator.score.should eq(5)

    mutator.adjust_score(3)
    mutator.score.should eq(8)

    mutator.adjust_score(10)
    mutator.score.should eq(10) # Max cap

    mutator.adjust_score(-20)
    mutator.score.should eq(2) # Min cap
  end
end
