require "./candidate"
require "../prng"

module Crowbar::Evolution
  # Population pool managing candidate test inputs scored by fitness.
  class Corpus
    property max_size : Int32
    getter candidates : Array(Candidate)

    def initialize(@max_size : Int32 = 64)
      @candidates = [] of Candidate
    end

    def size : Int32
      @candidates.size
    end

    def empty? : Bool
      @candidates.empty?
    end

    def clear
      @candidates.clear
    end

    # Adds a candidate to the population pool, sorted descending by fitness.
    def add(candidate : Candidate)
      @candidates << candidate
      @candidates.sort_by! { |c| -c.fitness }
      if @candidates.size > @max_size
        @candidates = @candidates[0...@max_size]
      end
    end

    def best : Candidate?
      @candidates.first?
    end

    # K-way Tournament Selection
    def tournament_select(prng : PRNG, k : Int32 = 4) : Candidate?
      return nil if empty?
      return @candidates.first if size == 1

      sample_size = [k, size].min
      participants = prng.sample(@candidates, sample_size)
      participants.max_by?(&.fitness)
    end

    # Fitness-proportional (Roulette Wheel) Selection
    def roulette_select(prng : PRNG) : Candidate?
      return nil if empty?
      return @candidates.first if size == 1

      min_fitness = @candidates.min_of(&.fitness)
      # Offset to handle negative or 0 fitness
      offset = min_fitness < 0 ? -min_fitness + 0.1 : 0.1
      total_fitness = @candidates.sum { |c| c.fitness + offset }

      r = prng.rand_float * total_fitness
      accum = 0.0

      @candidates.each do |c|
        accum += (c.fitness + offset)
        return c if accum >= r
      end
      @candidates.last
    end

    # Purges bottom half of population during stagnation to clear local minima
    def cull_stagnant(keep_ratio : Float64 = 0.5)
      keep_count = [1, (@candidates.size * keep_ratio).to_i].max
      @candidates = @candidates[0...keep_count]
    end
  end

  # Genetic operators for recombining candidates
  module Crossover
    # Slices and splices two candidates to create a hybrid offspring
    def self.recombine(parent_a : Buffer, parent_b : Buffer, prng : PRNG) : Buffer
      return parent_a.clone if parent_a.empty? || parent_b.empty?

      split_a = prng.rand(1..parent_a.size)
      split_b = prng.rand(0...parent_b.size)

      head = parent_a[0...split_a]
      tail = parent_b[split_b..]

      child = Buffer.new(head)
      child.insert(child.size, tail)
      child
    end
  end
end
