require "yaml"
require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for YAML.
  # Parses YAML document tree, mutates scalar values (numbers, strings, booleans)
  # or list items while maintaining valid document hierarchy and indentation.
  class YAMLRule < Rule
    def name : String
      "yaml"
    end

    def description : String
      "Structure-preserving YAML mutation (valid syntax with transformed values)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s.strip
      str.includes?(":") || str.starts_with?("---")
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_s
      parsed = YAML.parse(raw_str)
      mutated_raw = mutate_node(parsed.raw, context)

      new_yaml = mutated_raw.to_yaml
      buffer.replace_range(0, buffer.size, new_yaml.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_node(node : YAML::Any::Type, context : Context) : YAML::Any::Type
      case node
      when Int64
        mutate_int(node, context)
      when Float64
        mutate_float(node, context)
      when String
        mutate_string(node, context)
      when Bool
        !node
      when Array(YAML::Any)
        mutate_array(node, context)
      when Hash(YAML::Any, YAML::Any)
        mutate_mapping(node, context)
      else
        node
      end
    end

    private def mutate_int(val : Int64, context : Context) : YAML::Any::Type
      case context.prng.rand(4)
      when 0 then 0_i64
      when 1 then -1_i64
      when 2 then val &+ 1_i64
      else
        boundaries = [0_i64, 255_i64, 65535_i64, 2147483647_i64, Int64::MAX, Int64::MIN]
        context.prng.choice(boundaries)
      end
    end

    private def mutate_float(val : Float64, context : Context) : YAML::Any::Type
      case context.prng.rand(3)
      when 0 then 0.0
      when 1 then 1e308
      else        -1e308
      end
    end

    private def mutate_string(val : String, context : Context) : YAML::Any::Type
      case context.prng.rand(4)
      when 0 then ""
      when 1 then "A" * context.prng.rand_log(8)
      when 2 then "\u202E" + val
      else
        context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      end
    end

    private def mutate_array(arr : Array(YAML::Any), context : Context) : YAML::Any::Type
      new_arr = arr.map { |item| YAML::Any.new(item.raw) }
      return new_arr if new_arr.empty?

      case context.prng.rand(3)
      when 0 # Duplicate item
        item = context.prng.choice(new_arr)
        new_arr.insert(context.prng.rand(new_arr.size + 1), item)
      when 1 # Delete item
        new_arr.delete_at(context.prng.rand(new_arr.size)) if new_arr.size > 1
      else # Mutate item
        idx = context.prng.rand(new_arr.size)
        mutated_val = mutate_node(new_arr[idx].raw, context)
        new_arr[idx] = YAML::Any.new(mutated_val)
      end
      new_arr
    end

    private def mutate_mapping(hash : Hash(YAML::Any, YAML::Any), context : Context) : YAML::Any::Type
      new_hash = Hash(YAML::Any, YAML::Any).new
      hash.each { |k, v| new_hash[k] = YAML::Any.new(v.raw) }
      return new_hash if new_hash.empty?

      keys = new_hash.keys
      case context.prng.rand(3)
      when 0 # Duplicate key
        k = context.prng.choice(keys)
        new_k = YAML::Any.new(k.to_s + "_copy")
        new_hash[new_k] = new_hash[k]
      when 1 # Delete key
        if new_hash.size > 1
          k = context.prng.choice(keys)
          new_hash.delete(k)
        end
      else # Mutate value
        k = context.prng.choice(keys)
        mutated_val = mutate_node(new_hash[k].raw, context)
        new_hash[k] = YAML::Any.new(mutated_val)
      end
      new_hash
    end
  end
end
