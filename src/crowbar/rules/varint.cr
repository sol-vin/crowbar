require "./base"

module Crowbar::Rules
  # Structure-preserving rule for LEB128 / Protocol Buffers 7-bit continuation bit varints.
  # Parses variable-length integers, mutating values to boundary limits, injecting overlong
  # canonical violations, or testing continuation bit edge cases.
  class VarintRule < Rule
    struct VarintEntry
      getter offset : Int32
      getter length : Int32
      getter value : UInt64

      def initialize(@offset : Int32, @length : Int32, @value : UInt64)
      end
    end

    def name : String
      "varint"
    end

    def description : String
      "Structure-preserving LEB128/Protobuf 7-bit varint stream mutation"
    end

    def match?(buffer : Buffer) : Bool
      entries = parse_varints(buffer)
      !entries.empty?
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      entries = parse_varints(buffer)
      return false if entries.empty?

      entry = context.prng.choice(entries)

      replacement = case context.prng.rand(4)
                    when 0
                      # Boundary number varint
                      boundaries = [0_u64, 1_u64, 127_u64, 128_u64, 255_u64, 16383_u64, 16384_u64, 2147483647_u64, 4294967295_u64, UInt64::MAX]
                      encode_varint(context.prng.choice(boundaries))
                    when 1
                      # Overlong encoding: 5-byte encoding of value 1 (tests canonical rejection)
                      encode_overlong(entry.value, 5)
                    when 2
                      # Off-by-one
                      encode_varint(entry.value &+ (context.prng.rand_bool ? 1_u64 : UInt64::MAX))
                    else
                      # Set continuation bit on last byte (unterminated)
                      bytes = buffer[entry.offset, entry.length].dup
                      bytes[bytes.size - 1] |= 0x80_u8
                      bytes
                    end

      buffer.replace_range(entry.offset, entry.length, replacement)
      context.record_mutation(name, {entry.offset, entry.offset + replacement.size})
      true
    rescue
      false
    end

    private def parse_varints(buffer : Buffer) : Array(VarintEntry)
      entries = [] of VarintEntry
      pos = 0

      while pos < buffer.size
        # A varint starts where high bit may or may not be set
        # Check if we can parse a valid varint (up to 10 bytes for 64-bit)
        start_pos = pos
        val = 0_u64
        shift = 0
        valid = false

        while pos < buffer.size && (pos - start_pos) < 10
          b = buffer[pos]
          val |= ((b & 0x7F_u8).to_u64 << shift)
          pos += 1
          if (b & 0x80_u8) == 0
            valid = true
            break
          end
          shift += 7
        end

        if valid && pos > start_pos
          entries << VarintEntry.new(start_pos, pos - start_pos, val)
        else
          pos = start_pos + 1
        end
      end

      entries
    end

    private def encode_varint(value : UInt64) : Bytes
      io = IO::Memory.new
      v = value
      loop do
        byte = (v & 0x7F_u64).to_u8
        v >>= 7
        if v == 0
          io.write_byte(byte)
          break
        else
          io.write_byte(byte | 0x80_u8)
        end
      end
      io.to_slice
    end

    private def encode_overlong(value : UInt64, pad_to_bytes : Int32) : Bytes
      normal = encode_varint(value)
      return normal if normal.size >= pad_to_bytes

      io = IO::Memory.new
      # Set high continuation bit on all bytes of normal
      normal.each do |b|
        io.write_byte(b | 0x80_u8)
      end
      # Write zero-extended bytes
      needed_zeroes = pad_to_bytes - normal.size
      (needed_zeroes - 1).times do
        io.write_byte(0x80_u8)
      end
      io.write_byte(0x00_u8) # final terminating byte
      io.to_slice
    end
  end
end
