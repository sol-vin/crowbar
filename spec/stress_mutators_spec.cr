require "./spec_helper"
require "../src/crowbar/mutators/stress"

describe "Parser Robustness Mutators" do
  describe Crowbar::Mutators::NestingDepth do
    it "injects deeply nested delimiters for recursion testing" do
      mutator = Crowbar::Mutators::NestingDepth.new
      context = Crowbar::Context.new(42_u64)
      buffer = Crowbar::Buffer.new("data")

      success, delta = mutator.mutate(context, buffer)
      success.should be_true
      delta.should eq(2)
      buffer.size.should be > 60
      # Should contain paired brackets or braces
      str = buffer.to_s
      (str.includes?("[") || str.includes?("{") || str.includes?("(")).should be_true
    end
  end

  describe Crowbar::Mutators::LengthBoundary do
    it "replaces numeric length strings with boundary values" do
      mutator = Crowbar::Mutators::LengthBoundary.new
      context = Crowbar::Context.new(42_u64)
      buffer = Crowbar::Buffer.new("Content-Length: 1024\r\n")

      success, delta = mutator.mutate(context, buffer)
      success.should be_true
      delta.should eq(2)
      buffer.to_s.should_not eq("Content-Length: 1024\r\n")
    end
  end

  describe Crowbar::Mutators::FloatAnomalies do
    it "replaces floating-point values with IEEE-754 edge cases" do
      mutator = Crowbar::Mutators::FloatAnomalies.new
      context = Crowbar::Context.new(99_u64)
      buffer = Crowbar::Buffer.new("balance=123.45&rate=0.05")

      success, delta = mutator.mutate(context, buffer)
      success.should be_true
      delta.should eq(2)
      str = buffer.to_s
      (str.includes?("NaN") || str.includes?("Infinity") || str.includes?("1e") || str.includes?("0.0")).should be_true
    end
  end

  describe Crowbar::Mutators::DelimiterStress do
    it "injects unusual line breaks, folding, or repeated delimiters" do
      mutator = Crowbar::Mutators::DelimiterStress.new
      context = Crowbar::Context.new(777_u64)
      buffer = Crowbar::Buffer.new("header: value\r\nother: 123\r\n")

      success, delta = mutator.mutate(context, buffer)
      success.should be_true
      delta.should eq(1)
      buffer.size.should be > 26
    end
  end
end
