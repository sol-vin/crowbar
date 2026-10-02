require "./buffer"
require "./context"
require "./mutators/pool"
require "./patterns/base"
require "./selectors/base"
require "./rules/base"
require "./rules/json"
require "./rules/yaml"
require "./rules/http"
require "./rules/dns"
require "./rules/csv"
require "./rules/xml"
require "./rules/url"
require "./rules/tlv"
require "./rules/base64"
require "./rules/varint"
require "./evolution/manager"

module Crowbar
  # Represents a targeted scope within the pipeline
  class Scope
    getter name : String
    getter selector : Selector
    getter pool : MutatorPool
    getter rules : Array(Rule)
    property weight : Float64

    def initialize(@name : String, @selector : Selector, @weight : Float64 = 1.0)
      @pool = MutatorPool.new
      @rules = [] of Rule
    end

    def add_rule(rule : Rule)
      @rules << rule
    end
  end

  # Central transformation engine orchestrating PRNG state, scoped targets,
  # structure-preserving rules, adaptive mutator selection, and evolutionary feedback.
  class Engine
    getter context : Context
    getter pool : MutatorPool
    getter evolution : Evolution::Manager
    property pattern : Pattern
    getter scopes : Array(Scope)
    getter rules : Array(Rule)
    getter fixups : Array(Proc(Buffer, Nil))

    def initialize(seed : UInt64 = PRNG.default_seed)
      @context = Context.new(seed)
      @pool = MutatorPool.new
      @evolution = Evolution::Manager.new
      @pattern = Patterns::Many.new
      @scopes = [] of Scope
      @rules = [] of Rule
      @fixups = [] of Proc(Buffer, Nil)
    end

    def seed : UInt64
      @context.seed
    end

    def seed=(new_seed : UInt64)
      @context.seed = new_seed
    end

    def last_metadata : Metadata?
      @context.current_metadata
    end

    def add_scope(scope : Scope)
      @scopes << scope
    end

    def add_rule(rule : Rule)
      @rules << rule
    end

    def add_fixup(&block : Buffer -> Nil)
      @fixups << block
    end

    # Report feedback to evolutionary optimizer
    def report(candidate : Buffer | Bytes | String, fitness : Float64)
      @evolution.report(candidate, fitness)
    end

    def report(candidate : Buffer | Bytes | String, success : Bool)
      @evolution.report(candidate, success)
    end

    # Core transform method: transforms an input buffer and returns mutated buffer
    def transform(input : Buffer | Bytes | String) : Buffer
      baseline = case input
                 when Buffer then input
                 when Bytes  then Buffer.new(input)
                 else             Buffer.new(input.to_s)
                 end

      meta = @context.begin_iteration(baseline.size)

      # 1. Evolve: Select parent buffer (baseline or high-fitness candidate)
      working = @evolution.next_parent(baseline, @context.prng)

      # 2. Check and apply structure-preserving rules if configured or matched
      applied_rule = false
      @rules.each do |rule|
        if rule.match?(working)
          applied = rule.apply(@context, working)
          if applied
            applied_rule = true
            break
          end
        end
      end

      # 3. Apply targeted scopes or global pattern mutation
      unless applied_rule
        if @scopes.empty?
          # Global mutation using active pattern
          @pattern.apply(@context, working, @pool)
        else
          # Apply targeted scopes based on weight
          total_scope_weight = @scopes.sum(&.weight)
          @scopes.each do |sc|
            # Roll probability for scope activation
            prob = total_scope_weight > 0 ? (sc.weight / total_scope_weight) : 1.0
            if @context.prng.rand_bool(prob)
              target_ranges = sc.selector.select(working)
              target_ranges.reverse_each do |range|
                applied_scope_rule = false
                unless sc.rules.empty?
                  slice_len = range[1] - range[0]
                  if slice_len > 0 && range[0] >= 0 && range[1] <= working.size
                    sub_buf = Buffer.new(working[range[0], slice_len])
                    sc.rules.each do |rule|
                      if rule.match?(sub_buf) && rule.apply(@context, sub_buf)
                        working.replace_range(range[0], slice_len, sub_buf.to_slice)
                        applied_scope_rule = true
                        break
                      end
                    end
                  end
                end

                unless applied_scope_rule
                  @pattern.apply(@context, working, sc.pool, range) unless sc.pool.mutators.empty?
                end
              end
            end
          end
        end
      end

      # 4. Apply post-transform fixup hooks (e.g. recalculate length, checksums)
      @fixups.each do |fixup|
        fixup.call(working)
      end

      meta.output_size = working.size
      working
    end

    # Convenient alias
    def fuzz(input : Buffer | Bytes | String) : Buffer
      transform(input)
    end
  end
end
