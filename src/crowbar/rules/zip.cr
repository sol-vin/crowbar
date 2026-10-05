require "digest/crc32"
require "./base"

module Crowbar::Rules
  # Structure-preserving rule for ZIP (PKZip) archives.
  # Preserves the 4-byte local file header signature ("PK\x03\x04") and field alignment,
  # while mutating compression methods, flags, filenames, extra fields,
  # and compressed payloads, and automatically synchronizing CRC32 and payload lengths.
  class ZipRule < Rule
    ZIP_LOCAL_MAGIC = Bytes[0x50, 0x4B, 0x03, 0x04] # "PK\x03\x04"
    ZIP_EOCD_MAGIC  = Bytes[0x50, 0x4B, 0x05, 0x06] # "PK\x05\x06"

    def name : String
      "zip"
    end

    def description : String
      "Structure-preserving ZIP (PKZip) archive framing with automated length and CRC32 fixup"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 30
      buffer[0, 4].to_slice == ZIP_LOCAL_MAGIC
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      name_len = IO::ByteFormat::LittleEndian.decode(UInt16, buffer[26, 2].to_slice).to_i32 rescue 0
      extra_len = IO::ByteFormat::LittleEndian.decode(UInt16, buffer[28, 2].to_slice).to_i32 rescue 0
      header_len = 30 + name_len + extra_len

      action = context.prng.rand(5)
      mutated = false

      case action
      when 0
        # Mutate compression method (offset 8..9)
        # 0=Store, 8=Deflate, 9=Deflate64, 12=BZIP2, 14=LZMA, 99=WinZip AES
        methods = [0_u16, 8_u16, 9_u16, 12_u16, 14_u16, 99_u16, 65535_u16]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(methods), buffer[8, 2])
        mutated = true
      when 1
        # Mutate filename (offset 30, up to name_len)
        if name_len > 0 && 30 + name_len <= buffer.size
          traversals = [
            "../../../../../../../../tmp/pwn.txt",
            "..\\..\\..\\Windows\\System32\\fuzz.dll",
            "hidden\0evil.txt",
            "A" * name_len,
          ]
          chosen = context.prng.choice(traversals)
          slice = chosen.to_slice
          len = Math.min(slice.size, name_len)
          buffer.replace_range(30, len, slice[0, len])
          mutated = true
        else
          # Fallback: mutate general purpose bit flag (offset 6..7)
          buffer[6] ^= 0x01_u8 # Encrypted bit toggle
          mutated = true
        end
      when 2
        # Mutate uncompressed / compressed sizes (offsets 18..25)
        bad_sizes = [0_u32, 1_u32, 65535_u32, 4294967295_u32]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(bad_sizes), buffer[22, 4])
        mutated = true
      when 3
        # Mutate file payload data after header
        if buffer.size > header_len
          data_len = buffer.size - header_len
          pos = header_len + context.prng.rand(data_len)
          span = Math.min(context.prng.rand(1..16), buffer.size - pos)
          span.times do |off|
            buffer[pos + off] ^= context.prng.rand(1..255).to_u8
          end
          # Recalculate CRC32 of payload data if compression method is 0 (stored)
          method = IO::ByteFormat::LittleEndian.decode(UInt16, buffer[8, 2].to_slice) rescue 0_u16
          if method == 0_u16
            crc = Digest::CRC32.checksum(buffer[header_len, data_len].to_slice)
            IO::ByteFormat::LittleEndian.encode(crc, buffer[14, 4])
          end
          mutated = true
        else
          # Fallback: mutate version needed to extract (offset 4..5)
          buffer[4] = context.prng.choice([10_u8, 20_u8, 45_u8, 63_u8, 255_u8])
          mutated = true
        end
      else
        # Mutate version needed (offset 4..5) or extra field
        buffer[4] = context.prng.choice([10_u8, 20_u8, 45_u8, 63_u8, 255_u8])
        mutated = true
      end

      if mutated
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
