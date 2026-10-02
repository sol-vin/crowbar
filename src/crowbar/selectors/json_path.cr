require "json"

module Crowbar::Selectors
  # Selects values or keys associated with a specific key name inside JSON text.
  # Operates directly on byte offsets to support targeted AST mutations.
  class JSONKeyPath < Selector
    getter key : String
    getter? target_value : Bool

    def initialize(@key : String, @target_value : Bool = true, weight : Float64 = 1.0)
      super(weight)
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      str = buffer.to_raw_s
      matches = [] of Tuple(Int32, Int32)

      # Fast regex to locate key occurrences: "key"\s*:\s*
      escaped_key = ::Regex.escape(@key)
      pattern = /"#{escaped_key}"\s*:\s*/

      str.scan(pattern) do |m|
        if @target_value
          val_start = m.byte_end
          val_end = find_json_value_end(str, val_start)
          matches << {val_start, val_end} if val_end > val_start
        else
          # Target the key string quotes included
          key_start = m.byte_begin
          key_end = key_start + @key.bytesize + 2 # include quotes
          matches << {key_start, key_end}
        end
      end

      matches
    rescue ArgumentError
      [] of Tuple(Int32, Int32)
    end

    private def find_json_value_end(str : String, start_pos : Int32) : Int32
      bytes = str.to_slice
      pos = start_pos
      return pos if pos >= bytes.size

      # Skip initial whitespace
      while pos < bytes.size && (bytes[pos] == 0x20_u8 || bytes[pos] == 0x09_u8 || bytes[pos] == 0x0A_u8 || bytes[pos] == 0x0D_u8)
        pos += 1
      end
      return pos if pos >= bytes.size

      first_byte = bytes[pos]
      case first_byte
      when 0x22_u8 # String: "..."
        pos += 1
        escaped = false
        while pos < bytes.size
          b = bytes[pos]
          if escaped
            escaped = false
          elsif b == 0x5C_u8 # '\'
            escaped = true
          elsif b == 0x22_u8 # '"'
            return pos + 1
          end
          pos += 1
        end
        pos
      when 0x7B_u8 # Object: {...}
        depth = 0
        while pos < bytes.size
          b = bytes[pos]
          depth += 1 if b == 0x7B_u8
          depth -= 1 if b == 0x7D_u8
          if depth == 0
            return pos + 1
          end
          pos += 1
        end
        pos
      when 0x5B_u8 # Array: [...]
        depth = 0
        while pos < bytes.size
          b = bytes[pos]
          depth += 1 if b == 0x5B_u8
          depth -= 1 if b == 0x5D_u8
          if depth == 0
            return pos + 1
          end
          pos += 1
        end
        pos
      else
        # Primitive scalar: number, boolean, null (until comma, closing brace/bracket, or whitespace)
        while pos < bytes.size
          b = bytes[pos]
          if b == 0x2C_u8 || b == 0x7D_u8 || b == 0x5D_u8 || b == 0x0A_u8 || b == 0x0D_u8
            break
          end
          pos += 1
        end
        pos
      end
    end
  end
end
