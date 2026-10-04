require "../buffer"

module Crowbar::Evolution
  # Represents a scored individual candidate in the evolutionary population.
  class Candidate
    property buffer : Buffer
    property fitness : Float64
    property generation : Int64
    property mutation_history : Array(String)
    property feature : String?
    property coverage_hash : UInt64?

    def initialize(
      @buffer : Buffer,
      @fitness : Float64 = 0.0,
      @generation : Int64 = 0_i64,
      @mutation_history : Array(String) = [] of String,
      @feature : String? = nil,
      @coverage_hash : UInt64? = nil,
    )
    end

    def clone : Candidate
      Candidate.new(
        @buffer.clone,
        @fitness,
        @generation,
        @mutation_history.dup,
        @feature,
        @coverage_hash
      )
    end
  end
end
