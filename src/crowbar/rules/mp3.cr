require "./base"

module Crowbar::Rules
  # Structure-preserving rule for MPEG Audio Layer III (MP3) files and streams.
  # Preserves ID3v2 metadata headers and MPEG audio frame sync words (0xFF 0xE0+),
  # while mutating ID3 tags, MPEG audio frame headers (bitrates, sample frequencies,
  # channel modes, CRC protection), and audio bitstream payload frames.
  class MP3Rule < Rule
    def name : String
      "mp3"
    end

    def description : String
      "Structure-preserving MP3 ID3v2 tags and MPEG audio frame bitstream mutation"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 4

      # Check for ID3v2 tag prefix
      if buffer.size >= 10 && buffer[0, 3].to_slice == "ID3".to_slice
        return true
      end

      # Check for MPEG frame sync at offset 0
      if is_frame_sync?(buffer, 0)
        return true
      end

      # Scan first 512 bytes for MPEG frame sync
      max_scan = [buffer.size - 4, 512].min
      (0..max_scan).each do |i|
        return true if is_frame_sync?(buffer, i)
      end

      false
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      has_id3 = buffer.size >= 10 && buffer[0, 3].to_slice == "ID3".to_slice
      id3_size = has_id3 ? parse_id3_size(buffer) : 0

      # Locate MPEG audio frames
      frame_offsets = find_frame_offsets(buffer, id3_size)

      action = context.prng.rand(4)
      mutated = false

      case action
      when 0
        # Mutate ID3v2 tag metadata if present
        if has_id3 && id3_size > 10
          mutate_id3_tag(buffer, id3_size, context)
          mutated = true
        elsif !frame_offsets.empty?
          # Fallback to frame header mutation
          frame_off = context.prng.choice(frame_offsets)
          mutate_frame_header(buffer, frame_off, context)
          mutated = true
        end
      when 1
        # Mutate MPEG audio frame header (bitrate, sample rate, channels, protection)
        if !frame_offsets.empty?
          frame_off = context.prng.choice(frame_offsets)
          mutate_frame_header(buffer, frame_off, context)
          mutated = true
        end
      when 2
        # Mutate audio payload bytes within an MPEG frame
        if !frame_offsets.empty?
          frame_off = context.prng.choice(frame_offsets)
          mutate_frame_payload(buffer, frame_off, context)
          mutated = true
        end
      else
        # Fuzz arbitrary audio stream byte outside of frame sync words
        if buffer.size > id3_size + 4
          idx = id3_size + context.prng.rand(buffer.size - id3_size)
          # Ensure we don't accidentally wipe out an MPEG sync word 0xFF
          unless is_frame_sync?(buffer, idx) || (idx > 0 && is_frame_sync?(buffer, idx - 1))
            buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
            mutated = true
          end
        end
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

    # Checks if the given offset contains an MPEG audio frame sync (11 bits set)
    def is_frame_sync?(buffer : Buffer, offset : Int32) : Bool
      return false if offset + 4 > buffer.size
      b0 = buffer[offset]
      b1 = buffer[offset + 1]
      # 0xFF followed by top 3 bits set (0xE0)
      b0 == 0xFF_u8 && (b1 & 0xE0_u8) == 0xE0_u8
    end

    # Parses ID3v2 syncsafe integer size (10-byte header + tag size)
    private def parse_id3_size(buffer : Buffer) : Int32
      return 0 if buffer.size < 10
      b0 = buffer[6].to_i32
      b1 = buffer[7].to_i32
      b2 = buffer[8].to_i32
      b3 = buffer[9].to_i32
      tag_size = ((b0 & 0x7F) << 21) | ((b1 & 0x7F) << 14) | ((b2 & 0x7F) << 7) | (b3 & 0x7F)
      total = 10 + tag_size
      [total, buffer.size].min
    end

    # Scans buffer for MPEG audio frame header offsets
    def find_frame_offsets(buffer : Buffer, start_offset : Int32) : Array(Int32)
      offsets = [] of Int32
      pos = start_offset

      while pos + 4 <= buffer.size
        if is_frame_sync?(buffer, pos)
          offsets << pos
          # Skip ahead by rough frame header or size
          pos += 4
        else
          pos += 1
        end
        break if offsets.size >= 50
      end

      offsets
    end

    private def mutate_id3_tag(buffer : Buffer, id3_size : Int32, context : Context)
      return if id3_size <= 10

      case context.prng.rand(3)
      when 0
        # Mutate ID3 header flags (offset 5) or version (offset 3)
        if context.prng.rand_bool
          buffer[3] = context.prng.choice([2_u8, 3_u8, 4_u8, 255_u8]) # ID3v2.2, 2.3, 2.4, invalid
        else
          buffer[5] = buffer[5] ^ (1_u8 << context.prng.rand(8)) # Flags
        end
      when 1
        # Mutate metadata text inside the tag
        tag_payload_len = id3_size - 10
        if tag_payload_len > 0
          mut_idx = 10 + context.prng.rand(tag_payload_len)
          buffer[mut_idx] = context.prng.choice([0x00_u8, 0xFF_u8, 0x22_u8, 0x27_u8, 0x25_u8, 0x73_u8])
        end
      else
        # Inject boundary strings into ID3 payload
        tag_payload_len = id3_size - 10
        if tag_payload_len >= 8
          mut_idx = 10 + context.prng.rand(tag_payload_len - 4)
          boundary = context.prng.choice(["%s%s", "\x00\xFF\xFE", "\xFE\xFF", "A" * 8])
          boundary.to_slice.each_with_index do |b, i|
            buffer[mut_idx + i] = b if mut_idx + i < id3_size
          end
        end
      end
    end

    private def mutate_frame_header(buffer : Buffer, frame_off : Int32, context : Context)
      return if frame_off + 4 > buffer.size

      b1 = buffer[frame_off + 1]
      b2 = buffer[frame_off + 2]
      b3 = buffer[frame_off + 3]

      case context.prng.rand(4)
      when 0
        # Mutate MPEG Version / Layer / Protection bit in byte 1 (keep 11-bit sync intact)
        # Preserve top 3 sync bits (0xE0)
        sync_bits = b1 & 0xE0_u8
        sub_bits = context.prng.rand(32).to_u8
        buffer[frame_off + 1] = sync_bits | sub_bits
      when 1
        # Mutate Bitrate index (high 4 bits) or Sample rate index (bits 3..2) of byte 2
        bad_b2 = case context.prng.rand(3)
                 when 0 then (b2 & 0x0F_u8) | 0xF0_u8 # Bitrate 0xF (1111 = bad/reserved)
                 when 1 then (b2 & 0xF3_u8) | 0x0C_u8 # Sample rate 0x3 (11 = reserved)
                 else        b2 ^ (1_u8 << context.prng.rand(8))
                 end
        buffer[frame_off + 2] = bad_b2
      when 2
        # Mutate Channel mode (high 2 bits of byte 3) or Emphasis
        buffer[frame_off + 3] = b3 ^ (1_u8 << context.prng.rand(8))
      else
        # Toggle Protection CRC bit (bit 0 of byte 1)
        buffer[frame_off + 1] = b1 ^ 0x01_u8
      end
    end

    private def mutate_frame_payload(buffer : Buffer, frame_off : Int32, context : Context)
      # Audio frame data sits after 4-byte header
      start_payload = frame_off + 4
      return if start_payload >= buffer.size

      # Frame sizes typically range from 96 to 1440 bytes
      payload_len = [128, buffer.size - start_payload].min
      mut_count = context.prng.rand(1..4)
      mut_count.times do
        idx = start_payload + context.prng.rand(payload_len)
        buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
      end
    end
  end
end
