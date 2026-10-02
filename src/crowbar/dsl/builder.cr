require "../engine"

module Crowbar
  # DSL Builder for configuring Scopes, Selectors, and Mutators
  class ScopeBuilder
    getter scope : Scope

    def initialize(@scope : Scope)
    end

    def weight(val : Float64)
      @scope.weight = val
    end

    # Attach mutators by name
    def mutate(*names : Symbol)
      names.each do |name|
        case name
        when :byte_drop, :bd                           then @scope.pool.register(Mutators::ByteDrop.new)
        when :byte_flip, :bf                           then @scope.pool.register(Mutators::ByteFlip.new)
        when :byte_insert, :bi                         then @scope.pool.register(Mutators::ByteInsert.new)
        when :byte_repeat, :br                         then @scope.pool.register(Mutators::ByteRepeat.new)
        when :byte_permute, :bp                        then @scope.pool.register(Mutators::BytePermute.new)
        when :byte_inc_dec, :bei, :bed                 then @scope.pool.register(Mutators::ByteIncDec.new)
        when :byte_random, :ber                        then @scope.pool.register(Mutators::ByteRandom.new)
        when :sequence_repeat, :sr                     then @scope.pool.register(Mutators::SequenceRepeat.new)
        when :sequence_delete, :sd                     then @scope.pool.register(Mutators::SequenceDelete.new)
        when :sequence_swap, :ss                       then @scope.pool.register(Mutators::SequenceSwap.new)
        when :boundary_number, :boundary_numbers, :num then @scope.pool.register(Mutators::BoundaryNumbers.new)
        when :unicode, :unicode_edge_cases, :ui        then @scope.pool.register(Mutators::UnicodeEdgeCases.new)
        when :whitespace, :delimiters, :wd             then @scope.pool.register(Mutators::WhitespaceDelimiters.new)
        else
          # Allow string lookup
          if m = @scope.pool.find?(name.to_s)
            @scope.pool.register(m)
          end
        end
      end
    end
  end

  # DSL Builder for Genetic Algorithm and Evolutionary tuning
  class EvolutionBuilder
    getter manager : Evolution::Manager

    def initialize(@manager : Evolution::Manager)
    end

    def enabled(val : Bool)
      @manager.enabled = val
    end

    def population_size(val : Int32)
      @manager.corpus.max_size = val
    end

    def exploration_rate(val : Float64)
      @manager.exploration_rate = val
    end

    def crossover_rate(val : Float64)
      @manager.crossover_rate = val
    end

    def stagnation_limit(val : Int32)
      @manager.stagnation_limit = val
    end

    def selection(strategy : Symbol, size : Int32 = 4)
      @manager.selection_strategy = strategy
      @manager.tournament_size = size
    end
  end

  # Top-level DSL Builder for Crowbar
  class Builder
    getter engine : Engine

    def initialize(seed : UInt64? = nil)
      @engine = seed ? Engine.new(seed) : Engine.new
    end

    # Set PRNG seed
    def seed(val : UInt64 | Int32 | Int64)
      @engine.seed = val.to_u64
    end

    # Configure Genetic Algorithm & Feedback
    def evolution(&)
      builder = EvolutionBuilder.new(@engine.evolution)
      with builder yield builder
    end

    # Configure mutation pattern (:once, :many, :burst)
    def pattern(name : Symbol)
      @engine.pattern = case name
                        when :once, :od  then Patterns::Once.new
                        when :burst, :bu then Patterns::Burst.new
                        else                  Patterns::Many.new
                        end
    end

    # Enable structure-preserving rules (:json, :yaml, :http, :dns)
    def preserve(format : Symbol)
      case format
      when :json then @engine.add_rule(Rules::JSONRule.new)
      when :yaml then @engine.add_rule(Rules::YAMLRule.new)
      when :http then @engine.add_rule(Rules::HTTPRule.new)
      when :dns  then @engine.add_rule(Rules::DNSRule.new)
      end
    end

    def preserve_format(format : Symbol, &)
      preserve(format)
    end

    # Define a scoped byte range
    def scope(name : String | Symbol, bytes range : Range(B, E), &) forall B, E
      selector = Selectors::ByteRange.new(range)
      sc = Scope.new(name.to_s, selector)
      builder = ScopeBuilder.new(sc)
      with builder yield builder
      @engine.add_scope(sc)
    end

    # Define a scoped regex match
    def match(pattern : ::Regex, group : Int32 = 0, name : String? = nil, &)
      sc_name = name || "match_#{pattern.source}"
      selector = Selectors::Regex.new(pattern, group)
      sc = Scope.new(sc_name, selector)
      builder = ScopeBuilder.new(sc)
      with builder yield builder
      @engine.add_scope(sc)
    end

    # Register post-mutation fixup callback
    def fixup(&block : Buffer -> Nil)
      @engine.add_fixup(&block)
    end

    # Build and return the configured Engine
    def build : Engine
      @engine
    end
  end

  # Primary entry point for constructing a Crowbar pipeline
  def self.define(seed : UInt64? = nil, &) : Engine
    builder = Builder.new(seed)
    with builder yield builder
    builder.build
  end

  # Instant zero-config transform on data (Radamsa-style black box)
  def self.fuzz(input : Buffer | Bytes | String, seed : UInt64? = nil) : String
    engine = seed ? Engine.new(seed) : Engine.new
    engine.transform(input).to_s
  end
end
