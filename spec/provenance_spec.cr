require "./spec_helper"
require "../src/crowbar"

describe "Transformation Provenance & Process Trace" do
  it "records transformation steps with categories and coordinates" do
    engine = Crowbar::Engine.new(42_u64)
    engine.pool.mutators.clear

    # Register specific mutators
    pool = Crowbar::MutatorPool.new
    engine.pool.register(pool.find!("bf"))
    engine.pool.register(pool.find!("sec"))

    input = Crowbar::Buffer.new("Hello, World! Security boundary test string")
    output = engine.transform(input)

    meta = engine.last_metadata
    meta.should_not be_nil
    meta = meta.not_nil!

    meta.steps.size.should be > 0
    # Must have a parent selection step
    parent_step = meta.steps.find { |s| s.category == Crowbar::StepCategory::Parent }
    parent_step.should_not be_nil
    parent_step.not_nil!.name.should eq("baseline")

    # Must have mutator steps
    mutator_step = meta.steps.find { |s| s.category == Crowbar::StepCategory::Mutator }
    mutator_step.should_not be_nil
    ["bf", "sec"].should contain(mutator_step.not_nil!.name)
  end

  it "records scoped selector steps when target ranges are matched" do
    engine = Crowbar::Engine.new(1234_u64)
    scope = Crowbar::Scope.new("prefix", Crowbar::Selectors::Header.new(8), weight: 10.0)
    pool = Crowbar::MutatorPool.new
    scope.pool.register(pool.find!("bf"))
    engine.add_scope(scope)

    input = Crowbar::Buffer.new("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    output = engine.transform(input)

    meta = engine.last_metadata.not_nil!
    scope_step = meta.steps.find { |s| s.category == Crowbar::StepCategory::Selector }
    scope_step.should_not be_nil
    scope_step.not_nil!.name.should eq("prefix")
  end

  it "records rule recalculations and template envelope steps" do
    engine = Crowbar::Engine.new(999_u64)
    engine.template = "PREFIX[%f]SUFFIX"

    input = Crowbar::Buffer.new("Sample payload")
    output = engine.transform(input)

    meta = engine.last_metadata.not_nil!
    template_step = meta.steps.find { |s| s.category == Crowbar::StepCategory::Template }
    template_step.should_not be_nil
    template_step.not_nil!.diff_bytes.should be > 0
  end
end
