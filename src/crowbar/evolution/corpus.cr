require "./candidate"
require "../prng"

module Crowbar::Evolution
  # Population pool managing candidate test inputs scored by fitness,
  # augmented with multi-feature coverage bucketing for novelty preservation.
  class Corpus
    property max_size : Int32
    getter candidates : Array(Candidate)
    getter feature_buckets : Hash(String, Candidate)
    getter coverage_buckets : Hash(UInt64, Candidate)

    def initialize(@max_size : Int32 = 64)
      @candidates = [] of Candidate
      @feature_buckets = Hash(String, Candidate).new
      @coverage_buckets = Hash(UInt64, Candidate).new
    end

    def size : Int32
      all_unique_candidates.size
    end

    def empty? : Bool
      @candidates.empty? && @feature_buckets.empty? && @coverage_buckets.empty?
    end

    def clear
      @candidates.clear
      @feature_buckets.clear
      @coverage_buckets.clear
    end

    # Returns the combined set of general population and novelty feature representatives
    def all_unique_candidates : Array(Candidate)
      combined = @candidates.dup
      @feature_buckets.each_value do |cand|
        combined << cand unless combined.includes?(cand)
      end
      @coverage_buckets.each_value do |cand|
        combined << cand unless combined.includes?(cand)
      end
      combined
    end

    # Adds a candidate to the population pool.
    # If the candidate discovers an unseen feature or coverage hash, it is permanently bucketed.
    def add(candidate : Candidate) : Bool
      is_novel = false

      if feat = candidate.feature
        if existing = @feature_buckets[feat]?
          if candidate.fitness > existing.fitness
            @feature_buckets[feat] = candidate
            is_novel = true
          end
        else
          @feature_buckets[feat] = candidate
          is_novel = true
        end
      end

      if cov = candidate.coverage_hash
        if existing = @coverage_buckets[cov]?
          if candidate.fitness > existing.fitness
            @coverage_buckets[cov] = candidate
            is_novel = true
          end
        else
          @coverage_buckets[cov] = candidate
          is_novel = true
        end
      end

      @candidates << candidate
      @candidates.sort_by! { |c| -c.fitness }
      if @candidates.size > @max_size
        @candidates = @candidates[0...@max_size]
      end

      is_novel
    end

    def best : Candidate?
      all = all_unique_candidates
      all.max_by?(&.fitness)
    end

    # Checks if a feature tag has already been discovered
    def has_feature?(feature : String) : Bool
      @feature_buckets.has_key?(feature)
    end

    # Checks if a coverage hash has already been discovered
    def has_coverage_hash?(cov : UInt64) : Bool
      @coverage_buckets.has_key?(cov)
    end

    # K-way Tournament Selection across general and novelty candidates
    def tournament_select(prng : PRNG, k : Int32 = 4) : Candidate?
      pool = all_unique_candidates
      return nil if pool.empty?
      return pool.first if pool.size == 1

      sample_size = [k, pool.size].min
      participants = prng.sample(pool, sample_size)
      participants.max_by?(&.fitness)
    end

    # Fitness-proportional (Roulette Wheel) Selection
    def roulette_select(prng : PRNG) : Candidate?
      pool = all_unique_candidates
      return nil if pool.empty?
      return pool.first if pool.size == 1

      min_fitness = pool.min_of(&.fitness)
      offset = min_fitness < 0 ? -min_fitness + 0.1 : 0.1
      total_fitness = pool.sum { |c| c.fitness + offset }

      r = prng.rand_float * total_fitness
      accum = 0.0

      pool.each do |c|
        accum += (c.fitness + offset)
        return c if accum >= r
      end
      pool.last
    end

    # Purges bottom half of population during stagnation to clear local minima
    # Note: Novelty feature buckets are strictly preserved
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
