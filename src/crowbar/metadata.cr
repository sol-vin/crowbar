require "./transformation_step"

module Crowbar
  # Detailed metadata record for each transformation round.
  # Provides telemetry for mutations applied, modified offsets, and reproducibility.
  class Metadata
    property seed : UInt64
    property iteration : Int64
    property mutations_applied : Array(String)
    property modified_ranges : Array(Tuple(Int32, Int32))
    property steps : Array(TransformationStep)
    property input_size : Int32
    property output_size : Int32
    property fitness : Float64 = 0.0

    def initialize(
      @seed : UInt64 = 0_u64,
      @iteration : Int64 = 0_i64,
      @input_size : Int32 = 0,
      @output_size : Int32 = 0,
    )
      @mutations_applied = [] of String
      @modified_ranges = [] of Tuple(Int32, Int32)
      @steps = [] of TransformationStep
    end

    def record_mutation(name : String, range : Tuple(Int32, Int32)? = nil, description : String? = nil)
      @mutations_applied << name
      @modified_ranges << range if range
      desc = description || "Mutator '#{name}' applied"
      record_step(StepCategory::Mutator, name, desc, range)
    end

    def record_step(
      category : StepCategory,
      name : String,
      description : String,
      range : Tuple(Int32, Int32)? = nil,
      diff_bytes : Int32 = 0,
      details : Hash(String, String) = Hash(String, String).new,
    ) : TransformationStep
      r_start = range ? range[0] : nil
      r_end = range ? range[1] : nil
      step = TransformationStep.new(
        index: @steps.size + 1,
        category: category,
        name: name,
        description: description,
        range_start: r_start,
        range_end: r_end,
        diff_bytes: diff_bytes,
        details: details
      )
      @steps << step
      step
    end

    def to_s(io : IO)
      io << "Metadata(seed=" << @seed << ", iter=" << @iteration
      io << ", in=" << @input_size << "B, out=" << @output_size << "B"
      io << ", muts=[" << @mutations_applied.join(", ") << "]"
      io << ")"
    end
  end
end
