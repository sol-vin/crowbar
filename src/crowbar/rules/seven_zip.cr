require "digest/crc32"
require "./base"

module Crowbar::Rules
  # Structure-preserving rule for 7-Zip (7z) archives.
  # Preserves the 6-byte 7z file signature and 32-byte archive header structure,
  # while mutating archive version, NextHeader offsets, NextHeader sizes,
  # and compressed stream payloads, and automatically recalculating the StartHeader CRC32.
  class SevenZipRule < Rule
    SEVEN_ZIP_SIGNATURE = Bytes[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C] # '7', 'z', 0xBC, 0xAF, 0x27, 0x1C

    def name : String
      "7z"
    end

    def description : String
      "Structure-preserving 7-Zip (7z) archive framing with automated StartHeader CRC32 fixup"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 32
      buffer[0, 6].to_slice == SEVEN_ZIP_SIGNATURE
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      action = context.prng.rand(5)
      mutated = false

      case action
      when 0
        # Mutate NextHeaderOffset (bytes 12..19, UInt64 LE)
        offsets = [
          0_u64,
          1_u64,
          (buffer.size > 32 ? (buffer.size - 32).to_u64 : 0_u64),
          UInt32::MAX.to_u64,
          UInt64::MAX,
          context.prng.next_u64,
        ]
        chosen = context.prng.choice(offsets)
        IO::ByteFormat::LittleEndian.encode(chosen, buffer[12, 8])
        mutated = true
      when 1
        # Mutate NextHeaderSize (bytes 20..27, UInt64 LE)
        sizes = [
          0_u64,
          1_u64,
          (buffer.size > 32 ? (buffer.size - 32).to_u64 : 0_u64),
          65535_u64,
          UInt32::MAX.to_u64,
          UInt64::MAX,
        ]
        chosen = context.prng.choice(sizes)
        IO::ByteFormat::LittleEndian.encode(chosen, buffer[20, 8])
        mutated = true
      when 2
        # Mutate NextHeaderCRC (bytes 28..31, UInt32 LE)
        bad_crcs = [0_u32, 1_u32, 0xDEADBEEF_u32, UInt32::MAX, context.prng.next_u64.to_u32]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(bad_crcs), buffer[28, 4])
        mutated = true
      when 3
        # Mutate version bytes (bytes 6..7: major, minor)
        buffer[6] = context.prng.choice([0_u8, 1_u8, 2_u8, 0x7F_u8, 0xFF_u8])
        buffer[7] = context.prng.choice([0_u8, 4_u8, 9_u8, 0x7F_u8, 0xFF_u8])
        mutated = true
      else
        # Mutate archive stream payload after 32-byte header
        if buffer.size > 32
          payload_len = buffer.size - 32
          pos = 32 + context.prng.rand(payload_len)
          span = Math.min(context.prng.rand(1..16), buffer.size - pos)
          span.times do |off|
            buffer[pos + off] ^= context.prng.rand(1..255).to_u8
          end
          mutated = true
        else
          # Header-only buffer: mutate NextHeaderSize
          IO::ByteFormat::LittleEndian.encode(context.prng.rand(1..1024).to_u64, buffer[20, 8])
          mutated = true
        end
      end

      # Recalculate StartHeader CRC32 (CRC32 over bytes 12..31)
      if mutated
        crc = Digest::CRC32.checksum(buffer[12, 20].to_slice)
        IO::ByteFormat::LittleEndian.encode(crc, buffer[8, 4])
        context.record_mutation(name)
        true
      else
        false
      end
    rescue
      false
    end
  end
end
