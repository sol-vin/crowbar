require "json"
require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for JSON.
  # Parses the document AST, mutates leaf values (numbers, strings, booleans)
  # or structural bounds (arrays, objects) while guaranteeing valid JSON output.
  class JSONRule < Rule
    def name : String
      "json"
    end

    def description : String
      "Structure-preserving JSON mutation (valid syntax with transformed values)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s.strip
      (str.starts_with?('{') && str.ends_with?('}')) || (str.starts_with?('[') && str.ends_with?(']'))
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_s
      parsed = JSON.parse(raw_str)
      mutated_raw = mutate_node(parsed.raw, context)

      new_json = mutated_raw.to_json
      buffer.replace_range(0, buffer.size, new_json.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_node(node : JSON::Any::Type, context : Context) : JSON::Any::Type
      case node
      when Int64
        mutate_int(node, context)
      when Float64
        mutate_float(node, context)
      when String
        mutate_string(node, context)
      when Bool
        !node
      when Array(JSON::Any)
        mutate_array(node, context)
      when Hash(String, JSON::Any)
        mutate_object(node, context)
      else
        node
      end
    end

    private def mutate_int(val : Int64, context : Context) : JSON::Any::Type
      case context.prng.rand(5)
      when 0 then 0_i64
      when 1 then -1_i64
      when 2 then val &+ 1_i64
      when 3 then val &- 1_i64
      else
        # Boundary numbers
        boundaries = [127_i64, 255_i64, 32767_i64, 65535_i64, 2147483647_i64, 9007199254740991_i64, Int64::MAX, Int64::MIN]
        context.prng.choice(boundaries)
      end
    end

    private def mutate_float(val : Float64, context : Context) : JSON::Any::Type
      case context.prng.rand(4)
      when 0 then 0.0
      when 1 then -0.0
      when 2 then 1e308
      else        -1e308
      end
    end

    private def mutate_string(val : String, context : Context) : JSON::Any::Type
      case context.prng.rand(5)
      when 0 then ""                             # empty string
      when 1 then "A" * context.prng.rand_log(8) # repeated run
      when 2 then "\u202E" + val                 # BiDi override
      when 3 then "\u0000" + val                 # Leading null
      else
        # Number as string
        context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      end
    end

    private def mutate_array(arr : Array(JSON::Any), context : Context) : JSON::Any::Type
      new_arr = arr.map { |item| JSON::Any.new(item.raw) }
      return new_arr if new_arr.empty?

      case context.prng.rand(3)
      when 0 # Duplicate item
        item = context.prng.choice(new_arr)
        new_arr.insert(context.prng.rand(new_arr.size + 1), item)
      when 1 # Delete item
        new_arr.delete_at(context.prng.rand(new_arr.size)) if new_arr.size > 1
      else # Mutate an item
        idx = context.prng.rand(new_arr.size)
        mutated_val = mutate_node(new_arr[idx].raw, context)
        new_arr[idx] = JSON::Any.new(mutated_val)
      end
      new_arr
    end

    private def mutate_object(hash : Hash(String, JSON::Any), context : Context) : JSON::Any::Type
      new_hash = Hash(String, JSON::Any).new
      hash.each { |k, v| new_hash[k] = JSON::Any.new(v.raw) }
      return new_hash if new_hash.empty?

      keys = new_hash.keys
      case context.prng.rand(3)
      when 0 # Duplicate / variation of key
        k = context.prng.choice(keys)
        new_hash[k + "_extra"] = new_hash[k]
      when 1 # Delete a key
        if new_hash.size > 1
          k = context.prng.choice(keys)
          new_hash.delete(k)
        end
      else # Mutate a value
        k = context.prng.choice(keys)
        mutated_val = mutate_node(new_hash[k].raw, context)
        new_hash[k] = JSON::Any.new(mutated_val)
      end
      new_hash
    end
  end
end
