require "digest/crc32"
require "./base"

module Crowbar::Rules
  # Structure-preserving rule for Portable Network Graphics (PNG) images.
  # Preserves the 8-byte PNG file signature and valid chunk framing (IHDR, IDAT,
  # IEND, and auxiliary chunks), while mutating header dimensions, bit depths,
  # color types, scanline payloads, or chunk tags, and automatically recalculating
  # 4-byte chunk lengths and CRC32 checksums.
  class PNGRule < Rule
    PNG_SIGNATURE = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    struct Chunk
      getter type : String
      getter offset : Int32
      property length : Int32
      getter data_offset : Int32
      property crc_offset : Int32

      def initialize(@type : String, @offset : Int32, @length : Int32, @data_offset : Int32, @crc_offset : Int32)
      end
    end

    def name : String
      "png"
    end

    def description : String
      "Structure-preserving PNG chunk framing with automated CRC32 and length fixups"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 8
      buffer[0, 8].to_slice == PNG_SIGNATURE
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      chunks = parse_chunks(buffer)
      return false if chunks.empty?

      # Find key chunk types
      ihdr = chunks.find { |c| c.type == "IHDR" }
      idat_chunks = chunks.select { |c| c.type == "IDAT" }
      other_chunks = chunks.reject { |c| c.type == "IHDR" || c.type == "IEND" }

      action = context.prng.rand(4)
      mutated = false

      case action
      when 0
        # Mutate IHDR dimensions or parameters if available
        if ihdr && ihdr.length >= 13
          mutate_ihdr(ihdr, buffer, context)
          mutated = true
        end
      when 1
        # Mutate IDAT compressed payload bytes
        if !idat_chunks.empty?
          chunk = context.prng.choice(idat_chunks)
          mutate_chunk_data(chunk, buffer, context)
          mutated = true
        end
      when 2
        # Mutate auxiliary chunk or inject an auxiliary chunk before IEND
        if !other_chunks.empty? && context.prng.rand_bool
          chunk = context.prng.choice(other_chunks)
          mutate_chunk_data(chunk, buffer, context)
          mutated = true
        else
          mutated = inject_auxiliary_chunk(chunks, buffer, context)
        end
      else
        # Fuzz arbitrary chunk data and recalculate CRC
        chunk = context.prng.choice(chunks.reject { |c| c.type == "IEND" })
        mutate_chunk_data(chunk, buffer, context)
        mutated = true
      end

      if mutated
        # Ensure all chunk CRCs and lengths are properly synchronized
        recalculate_chunk_checksums(buffer)
        context.record_mutation(name)
        true
      else
        false
      end
    rescue
      false
    end

    # Parses all valid PNG chunks from the buffer
    def parse_chunks(buffer : Buffer) : Array(Chunk)
      chunks = [] of Chunk
      pos = 8 # Skip 8-byte PNG signature

      while pos + 12 <= buffer.size
        length = IO::ByteFormat::BigEndian.decode(UInt32, buffer[pos, 4].to_slice).to_i32
        break if length < 0 || pos + 12 + length > buffer.size

        type_slice = buffer[pos + 4, 4].to_slice
        type_str = String.new(type_slice) rescue "????"
        data_offset = pos + 8
        crc_offset = data_offset + length

        chunks << Chunk.new(type_str, pos, length, data_offset, crc_offset)
        pos = crc_offset + 4

        break if type_str == "IEND"
      end

      chunks
    end

    private def mutate_ihdr(chunk : Chunk, buffer : Buffer, context : Context)
      return if chunk.length < 13
      data_off = chunk.data_offset

      choice = context.prng.rand(4)
      case choice
      when 0
        # Mutate Width (4 bytes BE)
        width_boundary = [0_u32, 1_u32, 65535_u32, 2147483647_u32, 4294967295_u32, 16384_u32]
        new_width = context.prng.choice(width_boundary)
        IO::ByteFormat::BigEndian.encode(new_width, buffer[data_off, 4])
      when 1
        # Mutate Height (4 bytes BE)
        height_boundary = [0_u32, 1_u32, 65535_u32, 2147483647_u32, 4294967295_u32, 16384_u32]
        new_height = context.prng.choice(height_boundary)
        IO::ByteFormat::BigEndian.encode(new_height, buffer[data_off + 4, 4])
      when 2
        # Mutate Bit depth (offset 8) and Color type (offset 9)
        bad_bit_depths = [0_u8, 3_u8, 5_u8, 7_u8, 12_u8, 32_u8, 64_u8, 255_u8]
        buffer[data_off + 8] = context.prng.choice(bad_bit_depths)
      else
        # Mutate Compression (10), Filter (11), or Interlace (12)
        param_idx = context.prng.choice([10, 11, 12])
        buffer[data_off + param_idx] = context.prng.choice([1_u8, 2_u8, 5_u8, 255_u8])
      end

      # Recalculate CRC for IHDR chunk immediately
      update_chunk_crc(chunk, buffer)
    end

    private def mutate_chunk_data(chunk : Chunk, buffer : Buffer, context : Context)
      return if chunk.length == 0
      # Pick 1 to 4 random bytes in chunk data to mutate
      mut_count = [chunk.length, context.prng.rand(1..4)].min
      mut_count.times do
        idx = chunk.data_offset + context.prng.rand(chunk.length)
        buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
      end
      update_chunk_crc(chunk, buffer)
    end

    private def inject_auxiliary_chunk(chunks : Array(Chunk), buffer : Buffer, context : Context) : Bool
      iend = chunks.find { |c| c.type == "IEND" }
      insert_pos = iend ? iend.offset : buffer.size

      aux_types = ["tEXt", "pHYs", "gAMA", "cHRM", "sRGB", "tIME", "fUZZ"]
      chosen_type = context.prng.choice(aux_types)

      payload = case chosen_type
                when "gAMA"
                  # 4 bytes gamma value
                  val = context.prng.choice([0_u32, 100000_u32, 45455_u32, 4294967295_u32])
                  b = Bytes.new(4)
                  IO::ByteFormat::BigEndian.encode(val, b)
                  b
                when "pHYs"
                  # 9 bytes: 4B X, 4B Y, 1B unit
                  b = Bytes.new(9, 0_u8)
                  IO::ByteFormat::BigEndian.encode(2835_u32, b[0, 4])
                  IO::ByteFormat::BigEndian.encode(2835_u32, b[4, 4])
                  b[8] = 1_u8
                  b
                else
                  # Textual or random payload
                  comment = context.prng.choice(["Comment\x00FuzzTest", "Author\x00Crowbar", "Description\x00\xFF\xFE\x00"])
                  comment.to_slice
                end

      chunk_bytes = Bytes.new(12 + payload.size)
      IO::ByteFormat::BigEndian.encode(payload.size.to_u32, chunk_bytes[0, 4])
      chunk_bytes[4, 4].copy_from(chosen_type.to_slice)
      chunk_bytes[8, payload.size].copy_from(payload)

      # CRC over type + data
      crc = Digest::CRC32.checksum(chunk_bytes[4, 4 + payload.size])
      IO::ByteFormat::BigEndian.encode(crc, chunk_bytes[8 + payload.size, 4])

      # Insert into buffer before IEND
      buffer.insert(insert_pos, chunk_bytes)
      true
    end

    private def update_chunk_crc(chunk : Chunk, buffer : Buffer)
      return if chunk.crc_offset + 4 > buffer.size
      # CRC32 is calculated over chunk type (4 bytes) + chunk data (chunk.length bytes)
      crc_data = buffer[chunk.offset + 4, 4 + chunk.length].to_slice
      crc = Digest::CRC32.checksum(crc_data)
      IO::ByteFormat::BigEndian.encode(crc, buffer[chunk.crc_offset, 4])
    end

    private def recalculate_chunk_checksums(buffer : Buffer)
      chunks = parse_chunks(buffer)
      chunks.each do |c|
        update_chunk_crc(c, buffer)
      end
    end
  end
end
