require "base64"
require "./base"

module Crowbar::Rules
  # Structure-preserving rule for Base64 encoded payload streams.
  # Decodes inner raw binary data, applies Crowbar mutations to the decoded payload,
  # and re-encodes into valid Base64 with proper alphabet and padding.
  class Base64Rule < Rule
    def name : String
      "base64"
    end

    def description : String
      "Structure-preserving Base64 envelope mutation (decodes, mutates inner data, re-encodes)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s.strip
      return false if str.size < 4 || (str.size % 4 != 0)
      return false unless str.chars.all? { |c| c.ascii_alphanumeric? || c == '+' || c == '/' || c == '=' || c == '-' || c == '_' }

      Base64.decode(str)
      true
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_s.strip
      decoded = Base64.decode(raw_str)
      return false if decoded.empty?

      inner_buffer = Buffer.new(decoded)

      # Mutate decoded payload
      case context.prng.rand(4)
      when 0
        # Byte flip
        pos = context.prng.rand(inner_buffer.size)
        inner_buffer[pos] ^= (1_u8 << context.prng.rand(8))
      when 1
        # Byte insert
        pos = context.prng.rand(inner_buffer.size + 1)
        inner_buffer.insert(pos, context.prng.rand(256).to_u8)
      when 2
        # Byte drop
        if inner_buffer.size > 1
          pos = context.prng.rand(inner_buffer.size)
          inner_buffer.delete_at(pos)
        end
      else
        # Sequence repeat
        pos = context.prng.rand(inner_buffer.size)
        inner_buffer.insert(pos, inner_buffer[pos])
      end

      # Re-encode to valid Base64
      re_encoded = Base64.strict_encode(inner_buffer.to_slice)
      buffer.replace_range(0, buffer.size, re_encoded.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end
  end
end
