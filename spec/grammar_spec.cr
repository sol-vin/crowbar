require "./spec_helper"
require "../src/crowbar/dsl/grammar_builder"

describe "Context-Free Generative Grammar Engine" do
  it "generates structured strings using production rules" do
    fuzzer = Crowbar.define do
      seed 42_u64

      grammar :sql, max_depth: 4 do
        rule :start, ["SELECT ", :cols, " FROM ", :table]
        rule :cols, ["*"]
        choices :table, ["users", "orders", "audit_log"]
      end
    end

    fuzzer.grammars.has_key?("sql").should be_true
    query = fuzzer.generate(:sql)
    query.should start_with("SELECT * FROM ")
    (query.ends_with?("users") || query.ends_with?("orders") || query.ends_with?("audit_log")).should be_true
  end

  it "bounds recursion depth cleanly when recursive productions are used" do
    grammar = Crowbar::GrammarDefinition.new("nested", max_depth: 3)
    grammar.add_production(:start, [":", :expr, ":"])
    grammar.add_production(:expr, ["(", :expr, ")"], weight: 1.0)
    grammar.add_production(:expr, ["leaf"], weight: 0.1)

    prng = Crowbar::PRNG.new(123_u64)
    result = grammar.generate(:start, prng)

    result.should start_with(":")
    result.should end_with(":")
    # Must terminate without infinite loop and contain 'leaf'
    result.should contain("leaf")
  end
end
