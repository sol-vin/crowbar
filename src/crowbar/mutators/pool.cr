require "./base"
require "./byte"
require "./sequence"
require "./line"
require "./tree"
require "./values"

module Crowbar
  # Registry and adaptive selection engine for mutators.
  # Selects mutators based on their relative (effective_weight = score * user_weight)
  # and applies adaptive score feedback based on mutation success.
  class MutatorPool
    getter mutators : Array(Mutator)

    def initialize
      @mutators = [] of Mutator
      register_defaults
    end

    def register(mutator : Mutator)
      @mutators << mutator
    end

    def register_defaults
      # Byte mutators
      register(Mutators::ByteDrop.new)
      register(Mutators::ByteFlip.new)
      register(Mutators::ByteInsert.new)
      register(Mutators::ByteRepeat.new)
      register(Mutators::BytePermute.new)
      register(Mutators::ByteIncDec.new)
      register(Mutators::ByteRandom.new)

      # Sequence mutators
      register(Mutators::SequenceRepeat.new)
      register(Mutators::SequenceDelete.new)
      register(Mutators::SequenceSwap.new)

      # Line mutators
      register(Mutators::LineDelete.new)
      register(Mutators::LineDuplicate.new)
      register(Mutators::LineSwap.new)
      register(Mutators::LinePermute.new)

      # Tree mutators
      register(Mutators::TreeDelete.new)
      register(Mutators::TreeDuplicate.new)
      register(Mutators::TreeSwap.new)
      register(Mutators::TreeStutter.new)

      # Value mutators
      register(Mutators::BoundaryNumbers.new)
      register(Mutators::UnicodeEdgeCases.new)
      register(Mutators::WhitespaceDelimiters.new)
    end

    # Finds mutator by short or full name
    def find?(name : String) : Mutator?
      @mutators.find { |m| m.name == name }
    end

    # Selects a mutator based on weighted distribution
    def select_mutator(prng : PRNG) : Mutator
      raise "MutatorPool is empty" if @mutators.empty?

      total_weight = @mutators.sum(&.effective_weight)
      return prng.choice(@mutators) if total_weight <= 0.0

      r = prng.rand_float * total_weight
      accum = 0.0

      @mutators.each do |m|
        accum += m.effective_weight
        return m if accum >= r
      end

      @mutators.last
    end

    # Executes a mutation round, dynamically adjusting the selected mutator's score
    def mutate(
      context : Context,
      buffer : Buffer,
      target_range : Tuple(Int32, Int32)? = nil,
      preferred_mutator : Mutator? = nil,
    ) : Bool
      mutator = preferred_mutator || select_mutator(context.prng)
      mutated, delta = mutator.mutate(context, buffer, target_range)

      # Adaptive learning: update mutator score
      mutator.adjust_score(delta)
      mutated
    end
  end
end
