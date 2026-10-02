require "./spec_helper"
require "../src/crowbar/cli/diff"

describe "Crowbar CLI & HexDiff" do
  describe Crowbar::CLI::HexDiff do
    it "renders visual hex differences between original and mutated buffers" do
      original = Crowbar::Buffer.new("Hello, World! 123")
      mutated = Crowbar::Buffer.new("Hello, Fuzzd! 123")

      io = IO::Memory.new
      Crowbar::CLI::HexDiff.render(original, mutated, io)
      output = io.to_s

      output.should contain("=== Crowbar Hex Diff ===")
      output.should contain("Original Size: 17 B | Mutated Size: 17 B")
      output.should contain("00000000:")
      output.should contain("|")
    end

    it "renders diff cleanly when buffer lengths differ" do
      original = Crowbar::Buffer.new("Short")
      mutated = Crowbar::Buffer.new("Much Longer Mutated Output Buffer")

      io = IO::Memory.new
      Crowbar::CLI::HexDiff.render(original, mutated, io)
      output = io.to_s

      output.should contain("Original Size: 5 B | Mutated Size: 33 B")
      output.should contain("00000000:")
      output.should contain("00000010:")
      output.should contain("00000020:")
    end
  end

  describe "CLI Engine Configuration" do
    it "configures rules according to CLI rule arguments" do
      engine = Crowbar::Engine.new(42_u64)
      engine.rules.size.should eq(0)

      # JSON rule
      engine.add_rule(Crowbar::Rules::JSONRule.new)
      engine.rules.size.should eq(1)
      engine.rules.first.name.should eq("json")

      # CSV rule
      engine.add_rule(Crowbar::Rules::CSVRule.new)
      engine.rules.size.should eq(2)
      engine.rules.last.name.should eq("csv")
    end

    it "filters mutator pool according to CLI mutator selections" do
      engine = Crowbar::Engine.new(1234_u64)
      # Default pool contains all 30 mutators
      engine.pool.mutators.size.should eq(30)

      # Filter down to specific list (as done by CLI -m bd,bf)
      engine.pool.mutators.clear
      temp_pool = Crowbar::MutatorPool.new
      ["bd", "bf"].each do |name|
        if m = temp_pool.find?(name)
          engine.pool.register(m)
        end
      end

      engine.pool.mutators.size.should eq(2)
      engine.pool.mutators.map(&.name).should eq(["bd", "bf"])
    end

    it "configures patterns from CLI flags" do
      engine = Crowbar::Engine.new(5555_u64)

      engine.pattern = Crowbar::Patterns::Burst.new
      engine.pattern.name.should eq("bu")

      engine.pattern = Crowbar::Patterns::Once.new
      engine.pattern.name.should eq("od")

      engine.pattern = Crowbar::Patterns::Many.new
      engine.pattern.name.should eq("nd")
    end
  end
end
