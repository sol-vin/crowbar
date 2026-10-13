require "../buffer"
require "../rules/base"
require "../mutators/pool"
require "../patterns/base"

module Crowbar::Campaign
  # Categorization for targeted fuzzing endpoints
  enum TargetCategory
    Serialization
    Security
    Networking
    Grammar
    Archive
    Protocol
    Custom

    def to_s(io : IO) : Nil
      case self
      when Serialization then io << "Serialization"
      when Security      then io << "Security"
      when Networking    then io << "Networking"
      when Grammar       then io << "Grammar"
      when Archive       then io << "Archive"
      when Protocol      then io << "Protocol"
      when Custom        then io << "Custom"
      end
    end
  end

  # Represents a targeted test endpoint with corpus seeds, mutation rules,
  # expected non-fatal exception types, and execution boundary.
  class Target
    property name : String
    property category : TargetCategory
    property samples : Array(Buffer)
    property rules : Array(Rule)
    property mutator_pool : MutatorPool
    property pattern : Pattern
    property expected_errors : Array(Exception.class)
    property timeout : Time::Span
    property execution : Proc(Buffer, Nil)?

    def initialize(
      @name : String,
      @category : TargetCategory = TargetCategory::Custom,
      @samples : Array(Buffer) = [] of Buffer,
      @rules : Array(Rule) = [] of Rule,
      @expected_errors : Array(Exception.class) = [] of Exception.class,
      @timeout : Time::Span = 500.milliseconds,
      @execution : Proc(Buffer, Nil)? = nil,
    )
      @mutator_pool = MutatorPool.new
      @pattern = Patterns::Many.new
    end

    def add_sample(sample : Buffer | Bytes | String) : Nil
      buf = case sample
            when Buffer then sample
            when Bytes  then Buffer.new(sample)
            else             Buffer.new(sample.to_s)
            end
      @samples << buf
    end

    def add_rule(rule : Rule) : Nil
      @rules << rule
    end

    def add_expected_error(err_class : Exception.class) : Nil
      @expected_errors << err_class unless @expected_errors.includes?(err_class)
    end

    def expected_error?(ex : Exception) : Bool
      @expected_errors.any? { |cls| ex.class <= cls }
    end
  end
end
