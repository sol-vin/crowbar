require "../buffer"
require "../context"

module Crowbar
  # Base class for all data and byte mutators.
  # Incorporates Radamsa-inspired dynamic adaptive scoring (2..10) coupled with
  # user-configurable priority weights for intelligent selection.
  abstract class Mutator
    property weight : Float64 = 1.0
    property score : Int32 = 5 # Adaptive score between 2 and 10

    def initialize(@weight : Float64 = 1.0)
    end

    abstract def name : String
    abstract def description : String

    # Optional short aliases or alternative identifiers (e.g. ["fuse", "ft", "fn"])
    def aliases : Array(String)
      [] of String
    end

    # Performs mutation on buffer, optionally constrained to target_range [start, end_exclusive].
    # Returns a tuple of {success : Bool, score_delta : Int32}.
    # score_delta > 0 indicates success in an appropriate domain (+1 or +2).
    # score_delta < 0 indicates the input does not match the mutator's domain (-1).
    abstract def mutate(
      context : Context,
      buffer : Buffer,
      target_range : Tuple(Int32, Int32)? = nil,
    ) : Tuple(Bool, Int32)

    # Adjust dynamic score within [2, 10]
    def adjust_score(delta : Int32)
      @score = [2, [10, @score + delta].min].max
    end

    # Probability multiplier: score * user_weight
    def effective_weight : Float64
      @score.to_f64 * @weight
    end

    # Helper to resolve actual slice boundaries
    protected def resolve_range(buffer : Buffer, target_range : Tuple(Int32, Int32)?) : Tuple(Int32, Int32)
      if r = target_range
        b = [0, [r[0], buffer.size].min].max
        e = [b, [r[1], buffer.size].min].max
        {b, e}
      else
        {0, buffer.size}
      end
    end
  end
end
