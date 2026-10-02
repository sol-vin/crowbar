require "../buffer"
require "../context"

module Crowbar
  # Base class for structure-preserving rule engines.
  # Rules understand specific formats (JSON, YAML, HTTP, DNS) and ensure that
  # the structural framing remains syntactically valid while underlying values are mutated.
  abstract class Rule
    property weight : Float64 = 1.0

    def initialize(@weight : Float64 = 1.0)
    end

    abstract def name : String
    abstract def description : String

    # Checks whether the buffer matches the format handled by this rule
    abstract def match?(buffer : Buffer) : Bool

    # Applies a structure-preserving transformation to the buffer
    abstract def apply(context : Context, buffer : Buffer) : Bool
  end
end
