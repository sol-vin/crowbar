require "./spec_helper"

describe "Extended Mutator Families" do
  it "registers all new mutators in MutatorPool defaults" do
    pool = Crowbar::MutatorPool.new
    ["bfr", "wb", "scale", "time", "cf", "homo", "dict", "pad", "trunc"].each do |code|
      pool.find?(code).should_not be_nil
    end
  end

  it "flips contiguous bit runs with BitFlipRun" do
    buffer = Crowbar::Buffer.new(Bytes.new(8, 0x00_u8))
    context = Crowbar::Context.new(42_u64)
    mutator = Crowbar::Mutators::BitFlipRun.new

    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    buffer.to_slice.any? { |b| b != 0x00_u8 }.should be_true
  end

  it "slides a single bit with WalkingBit" do
    buffer = Crowbar::Buffer.new(Bytes.new(4, 0x00_u8))
    context = Crowbar::Context.new(123_u64)
    mutator = Crowbar::Mutators::WalkingBit.new

    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    # Exactly 1 bit set across the buffer
    total_bits = buffer.to_slice.sum { |b| b.popcount }
    total_bits.should eq(1)
  end

  it "scales textual numbers with ArithmeticScaler" do
    buffer = Crowbar::Buffer.new("count: 50 items")
    context = Crowbar::Context.new(99_u64)
    mutator = Crowbar::Mutators::ArithmeticScaler.new

    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    # Number 50 should have changed
    buffer.to_s.should_not eq("count: 50 items")
  end

  it "substitutes temporal timestamps with TimestampMutator" do
    buffer = Crowbar::Buffer.new("created_at: 1727800000")
    context = Crowbar::Context.new(777_u64)
    mutator = Crowbar::Mutators::TimestampMutator.new

    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    buffer.to_s.should_not eq("created_at: 1727800000")
  end

  it "alters letter casing with CaseFlip" do
    buffer = Crowbar::Buffer.new("HELLO world")
    context = Crowbar::Context.new(333_u64)
    mutator = Crowbar::Mutators::CaseFlip.new

    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    buffer.to_s.should_not eq("HELLO world")
  end

  it "injects Unicode homoglyphs with HomoglyphMutator" do
    buffer = Crowbar::Buffer.new("apple")
    context = Crowbar::Context.new(555_u64)
    mutator = Crowbar::Mutators::HomoglyphMutator.new

    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    # 'a' or 'p' or 'e' replaced with Cyrillic lookalike, increasing UTF-8 byte size
    buffer.size.should be >= 5
    buffer.to_s.should_not eq("apple")
  end

  it "inserts vocabulary tokens with DictionaryMutator" do
    buffer = Crowbar::Buffer.new("user_session")
    context = Crowbar::Context.new(888_u64)
    mutator = Crowbar::Mutators::DictionaryMutator.new(["SECRET_TOKEN"])

    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    buffer.to_s.should contain("SECRET_TOKEN")
  end

  it "pads buffer with PaddingMutator" do
    buffer = Crowbar::Buffer.new("short")
    context = Crowbar::Context.new(111_u64)
    mutator = Crowbar::Mutators::PaddingMutator.new

    initial_size = buffer.size
    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    buffer.size.should be > initial_size
  end

  it "truncates buffer with TruncationMutator" do
    buffer = Crowbar::Buffer.new("Line 1\nLine 2\nLine 3\nLine 4\n")
    context = Crowbar::Context.new(222_u64)
    mutator = Crowbar::Mutators::TruncationMutator.new

    initial_size = buffer.size
    mutated, _ = mutator.mutate(context, buffer)
    mutated.should be_true
    buffer.size.should be < initial_size
  end
end
