require "./base"
require "./byte"
require "./sequence"
require "./line"
require "./tree"
require "./values"
require "./bit"
require "./arithmetic"
require "./text"
require "./layout"
require "./stress"
require "./splice"
require "./security"
require "../evolution/bandit"

module Crowbar
  # Registry and adaptive selection engine for mutators.
  # Supports both adaptive score weighting and UCB1 Multi-Armed Bandit credit assignment.
  class MutatorPool
    getter mutators : Array(Mutator)
    property bandit : Evolution::Bandit?
    property use_bandit : Bool = false

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

      # Bit mutators
      register(Mutators::BitFlipRun.new)
      register(Mutators::WalkingBit.new)

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

      # Arithmetic & Temporal mutators
      register(Mutators::ArithmeticScaler.new)
      register(Mutators::TimestampMutator.new)

      # Text & Encoding mutators
      register(Mutators::CaseFlip.new)
      register(Mutators::HomoglyphMutator.new)
      register(Mutators::DictionaryMutator.new)

      # Layout & Structure mutators
      register(Mutators::PaddingMutator.new)
      register(Mutators::TruncationMutator.new)

      # Parser Robustness & Boundary mutators
      register(Mutators::NestingDepth.new)
      register(Mutators::LengthBoundary.new)
      register(Mutators::FloatAnomalies.new)
      register(Mutators::DelimiterStress.new)

      # Sequence Splicing & Parser Boundary Validation
      register(Mutators::Splice.new)
      register(Mutators::Security.new)
    end

    # Finds mutator by short or full name or alias
    def find?(name : String) : Mutator?
      clean = name.strip.downcase
      @mutators.find { |m| m.name.downcase == clean || m.aliases.map(&.downcase).includes?(clean) }
    end

    # Finds mutator by name or raises an exception
    def find!(name : String) : Mutator
      find?(name) || raise KeyError.new("Mutator not found: #{name}")
    end

    # Selects a mutator based on weighted distribution or UCB1 bandit score
    def select_mutator(prng : PRNG, bandit_override : Evolution::Bandit? = nil) : Mutator
      raise "MutatorPool is empty" if @mutators.empty?

      active_bandit = bandit_override || @bandit
      if @use_bandit && active_bandit
        arm_names = @mutators.map(&.name)
        chosen_name = active_bandit.select(arm_names, prng)
        active_bandit.record_pull(chosen_name)
        if m = find?(chosen_name)
          return m
        end
      end

      # Standard weighted roulette
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
      bandit_override : Evolution::Bandit? = nil,
    ) : Bool
      mutator = preferred_mutator || select_mutator(context.prng, bandit_override)
      mutated, delta = mutator.mutate(context, buffer, target_range)

      # Adaptive learning: update mutator score
      mutator.adjust_score(delta)
      mutated
    end
  end
end
