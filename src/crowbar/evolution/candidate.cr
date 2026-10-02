require "../buffer"

module Crowbar::Evolution
  # Represents a scored individual candidate in the evolutionary population.
  class Candidate
    property buffer : Buffer
    property fitness : Float64
    property generation : Int64
    property mutation_history : Array(String)

    def initialize(
      @buffer : Buffer,
      @fitness : Float64 = 0.0,
      @generation : Int64 = 0_i64,
      @mutation_history : Array(String) = [] of String,
    )
    end

    def clone : Candidate
      Candidate.new(@buffer.clone, @fitness, @generation, @mutation_history.dup)
    end
  end
end
