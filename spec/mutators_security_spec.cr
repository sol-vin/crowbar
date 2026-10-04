require "./spec_helper"

describe Crowbar::Mutators::Security do
  it "has clean QA naming (sec) and aliases (ab, bad_ascii, security)" do
    mutator = Crowbar::Mutators::Security.new
    mutator.name.should eq("sec")
    mutator.aliases.should eq(["ab", "bad_ascii", "security"])
    mutator.description.should contain("parser boundary test vectors")
  end

  it "is discoverable in MutatorPool by sec, ab, bad_ascii, and security" do
    pool = Crowbar::MutatorPool.new
    pool.find?("sec").should_not be_nil
    pool.find?("ab").should_not be_nil
    pool.find?("bad_ascii").should_not be_nil
    pool.find?("security").should_not be_nil
  end

  it "injects boundary test vectors (format strings, traversal, null bytes, escapes) into buffer" do
    mutator = Crowbar::Mutators::Security.new
    context = Crowbar::Context.new(777_u64)
    buffer = Crowbar::Buffer.new("filename=report.csv&user=admin")

    success, delta = mutator.mutate(context, buffer)
    success.should be_true
    delta.should eq(1)

    # Mutant should differ from original
    mutated_str = buffer.to_s
    mutated_str.should_not eq("filename=report.csv&user=admin")
  end

  it "respects targeted ranges when mutating" do
    mutator = Crowbar::Mutators::Security.new
    context = Crowbar::Context.new(456_u64)
    buffer = Crowbar::Buffer.new("AAAA|BBBB|CCCC")

    # Target only the "BBBB" section (index 5 to 9)
    success, delta = mutator.mutate(context, buffer, target_range: {5, 9})
    success.should be_true
    # "AAAA|" prefix should remain intact
    buffer.to_s.should start_with("AAAA|")
  end
end
