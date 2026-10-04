require "../buffer"
require "../context"
require "../mutators/pool"

module Crowbar
  # Abstract execution pattern governing how mutations are orchestrated.
  abstract class Pattern
    property weight : Float64 = 1.0

    def initialize(@weight : Float64 = 1.0)
    end

    abstract def name : String
    abstract def description : String

    # Applies one or more mutations to the buffer according to the pattern's strategy.
    abstract def apply(
      context : Context,
      buffer : Buffer,
      pool : MutatorPool,
      target_range : Tuple(Int32, Int32)? = nil,
    ) : Bool
  end

  module Patterns
    # Applies exactly one mutation
    class Once < Pattern
      def name : String
        "od"
      end

      def description : String
        "Mutate once"
      end

      def apply(
        context : Context,
        buffer : Buffer,
        pool : MutatorPool,
        target_range : Tuple(Int32, Int32)? = nil,
      ) : Bool
        8.times do
          return true if pool.mutate(context, buffer, target_range)
        end
        false
      end
    end

    # Applies one or more mutations with decaying probability
    class Many < Pattern
      property decay_probability : Float64 = 0.55

      def name : String
        "nd"
      end

      def description : String
        "Mutate multiple times with geometric probability decay"
      end

      def apply(
        context : Context,
        buffer : Buffer,
        pool : MutatorPool,
        target_range : Tuple(Int32, Int32)? = nil,
      ) : Bool
        mutated_any = false
        attempts = 0
        loop do
          mutated = pool.mutate(context, buffer, target_range)
          mutated_any ||= mutated
          attempts += 1
          if !mutated_any && attempts < 8
            next
          end
          break unless context.prng.rand_bool(@decay_probability)
        end
        mutated_any
      end
    end

    # Applies a burst of multiple mutations clustered close to each other
    class Burst < Pattern
      def name : String
        "bu"
      end

      def description : String
        "Mutate in a localized burst of several changes"
      end

      def apply(
        context : Context,
        buffer : Buffer,
        pool : MutatorPool,
        target_range : Tuple(Int32, Int32)? = nil,
      ) : Bool
        return false if buffer.empty?

        # Select a sub-region for the burst
        b, e = if r = target_range
                 {r[0], r[1]}
               else
                 {0, buffer.size}
               end

        len = e - b
        return false if len <= 0

        # Narrow down to a localized window
        window_size = [len, 32].min
        start_pos = b + (len > window_size ? context.prng.rand(len - window_size + 1) : 0)
        burst_range = {start_pos, start_pos + window_size}

        burst_count = context.prng.rand(2..8)
        mutated_any = false

        burst_count.times do
          mutated = pool.mutate(context, buffer, burst_range)
          mutated_any ||= mutated
        end
        mutated_any
      end
    end

    # Resolves a pattern by name or alias ("once"/"od", "burst"/"bu", "many"/"nd")
    def self.create?(name : String) : Pattern?
      case name.strip.downcase
      when "od", "once"  then Once.new
      when "bu", "burst" then Burst.new
      when "nd", "many"  then Many.new
      else                    nil
      end
    end

    # Catalog of available patterns with canonical name, alias, and description
    def self.catalog : Array(Tuple(String, String, String))
      [
        {"many", "nd", "Mutate multiple times with geometric probability decay (default)"},
        {"burst", "bu", "Mutate in a localized burst of several changes"},
        {"once", "od", "Mutate once"},
      ]
    end
  end
end
