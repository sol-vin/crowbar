require "../buffer"
require "../prng"

module Crowbar
  # Context-free generative grammar engine with bounded recursion depth.
  class GrammarDefinition
    class Production
      getter tokens : Array(String | Symbol)
      property weight : Float64

      def initialize(tokens : Iterable(String | Symbol), @weight : Float64 = 1.0)
        @tokens = tokens.map(&.as(String | Symbol)).to_a
      end

      # Returns true if all tokens are string literals (terminal)
      def terminal? : Bool
        @tokens.none?(&.is_a?(Symbol))
      end
    end

    getter name : String
    property max_depth : Int32 = 8
    getter rules : Hash(Symbol, Array(Production))

    def initialize(@name : String, @max_depth : Int32 = 8)
      @rules = Hash(Symbol, Array(Production)).new
    end

    # Adds a production for a non-terminal rule
    def add_production(rule_name : Symbol, tokens : Iterable(String | Symbol), weight : Float64 = 1.0)
      @rules[rule_name] ||= [] of Production
      @rules[rule_name] << Production.new(tokens, weight)
    end

    # Generates a string starting from start_symbol
    def generate(start_symbol : Symbol = :start, prng : PRNG = PRNG.new) : String
      io = IO::Memory.new
      expand(start_symbol, 0, io, prng)
      io.to_s
    end

    # Recursively expands a non-terminal symbol
    private def expand(symbol : Symbol, depth : Int32, io : IO, prng : PRNG)
      productions = @rules[symbol]?
      return if productions.nil? || productions.empty?

      # If depth limit exceeded, force selection of a terminal production if available
      selected = if depth >= @max_depth
                   terminals = productions.select(&.terminal?)
                   terminals.empty? ? productions.first : prng.choice(terminals)
                 else
                   select_weighted(productions, prng)
                 end

      selected.tokens.each do |token|
        case token
        when String
          io << token
        when Symbol
          expand(token, depth + 1, io, prng)
        end
      end
    end

    private def select_weighted(productions : Array(Production), prng : PRNG) : Production
      return productions.first if productions.size == 1

      total_weight = productions.sum(&.weight)
      return prng.choice(productions) if total_weight <= 0.0

      r = prng.rand_float * total_weight
      accum = 0.0

      productions.each do |p|
        accum += p.weight
        return p if accum >= r
      end

      productions.last
    end
  end

  # DSL builder for defining context-free grammars
  class GrammarBuilder
    getter grammar : GrammarDefinition

    def initialize(name : String | Symbol, max_depth : Int32 = 8)
      @grammar = GrammarDefinition.new(name.to_s, max_depth)
    end

    def max_depth(val : Int32)
      @grammar.max_depth = val
    end

    # Define a production rule with an array of tokens and optional weight
    def rule(name : Symbol, tokens : Iterable(String | Symbol), weight : Float64 = 1.0)
      @grammar.add_production(name, tokens, weight)
    end

    # Convenience overload for passing multiple string/symbol arguments
    def rule(name : Symbol, *tokens : String | Symbol, weight : Float64 = 1.0)
      @grammar.add_production(name, tokens.to_a, weight)
    end

    # Convenience overload for list of terminal string options (shorthand for single-token choices)
    def choices(name : Symbol, options : Iterable(String), weight : Float64 = 1.0)
      options.each do |opt|
        @grammar.add_production(name, [opt.as(String | Symbol)], weight)
      end
    end
  end
end
