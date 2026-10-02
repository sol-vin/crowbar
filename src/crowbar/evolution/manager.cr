require "./corpus"
require "../buffer"
require "../prng"

module Crowbar::Evolution
  # Coordinates genetic algorithm feedback, selection, crossover, and anti-stagnation.
  class Manager
    property enabled : Bool = true
    property exploration_rate : Float64 = 0.15 # 15% guaranteed random exploration (anti-locking)
    property crossover_rate : Float64 = 0.25   # 25% genetic crossover between high-fitness pairs
    property stagnation_limit : Int32 = 100    # Stagnant round limit before novelty injection
    property selection_strategy : Symbol = :tournament
    property tournament_size : Int32 = 4

    getter corpus : Corpus
    getter stagnation_count : Int32 = 0
    getter last_best_fitness : Float64 = -1e9
    getter total_evaluations : Int64 = 0_i64

    def initialize(population_size : Int32 = 64)
      @corpus = Corpus.new(population_size)
    end

    # Report fitness outcome for a candidate (continuous score)
    def report(data : Buffer | Bytes | String, fitness : Float64)
      return unless @enabled
      @total_evaluations += 1

      buf = case data
            when Buffer then data
            when Bytes  then Buffer.new(data)
            else             Buffer.new(data.to_s)
            end

      candidate = Candidate.new(buf.clone, fitness: fitness)
      @corpus.add(candidate)
      check_stagnation
    end

    # Report binary success outcome (converted to fitness 1.0 vs 0.0)
    def report(data : Buffer | Bytes | String, success : Bool)
      report(data, success ? 1.0 : 0.0)
    end

    # Selects or generates the starting parent buffer for the next mutation round
    def next_parent(baseline : Buffer, prng : PRNG) : Buffer
      # 1. If disabled, or population empty, or exploration rate triggers, use fresh baseline
      if !@enabled || @corpus.empty? || prng.rand_bool(@exploration_rate)
        return baseline.clone
      end

      # 2. Crossover recombination if configured and multiple candidates exist
      if @corpus.size >= 2 && prng.rand_bool(@crossover_rate)
        p1 = select_individual(prng)
        p2 = select_individual(prng)
        if p1 && p2
          return Crossover.recombine(p1.buffer, p2.buffer, prng)
        end
      end

      # 3. Standard selection from scored population
      if selected = select_individual(prng)
        selected.buffer.clone
      else
        baseline.clone
      end
    end

    private def select_individual(prng : PRNG) : Candidate?
      case @selection_strategy
      when :roulette
        @corpus.roulette_select(prng)
      else
        @corpus.tournament_select(prng, @tournament_size)
      end
    end

    # Detects local plateauing / loops and injects entropy
    private def check_stagnation
      best = @corpus.best
      return unless best

      if best.fitness > @last_best_fitness + 1e-6
        # Progress made!
        @last_best_fitness = best.fitness
        @stagnation_count = 0
      else
        @stagnation_count += 1
        if @stagnation_count >= @stagnation_limit
          # Stagnation reached: inject novelty and clear stale local minima
          @corpus.cull_stagnant(0.5)
          @stagnation_count = 0
        end
      end
    end
  end
end
