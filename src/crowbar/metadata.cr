module Crowbar
  # Detailed metadata record for each transformation round.
  # Provides telemetry for mutations applied, modified offsets, and reproducibility.
  class Metadata
    property seed : UInt64
    property iteration : Int64
    property mutations_applied : Array(String)
    property modified_ranges : Array(Tuple(Int32, Int32))
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
    end

    def record_mutation(name : String, range : Tuple(Int32, Int32)? = nil)
      @mutations_applied << name
      @modified_ranges << range if range
    end

    def to_s(io : IO)
      io << "Metadata(seed=" << @seed << ", iter=" << @iteration
      io << ", in=" << @input_size << "B, out=" << @output_size << "B"
      io << ", muts=[" << @mutations_applied.join(", ") << "]"
      io << ")"
    end
  end
end
