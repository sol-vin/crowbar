require "./base"

module Crowbar::Rules
  # Structure-preserving rule for Type-Length-Value (TLV) binary record streams.
  # Parses 2-byte Tag and 2-byte Big-Endian Length framing:
  # [Tag: UInt16][Length: UInt16][Value: Length bytes]
  class TLVRule < Rule
    struct Frame
      property tag : UInt16
      property value : Bytes

      def initialize(@tag : UInt16, @value : Bytes)
      end
    end

    def name : String
      "tlv"
    end

    def description : String
      "Structure-preserving Type-Length-Value (TLV) binary packet frame mutation"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 4
      frames = parse_frames(buffer)
      frames.size >= 1
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      frames = parse_frames(buffer)
      return false if frames.empty?

      frame_idx = context.prng.rand(frames.size)
      frame = frames[frame_idx]

      case context.prng.rand(4)
      when 0
        # Mutate Tag ID
        frame.tag = context.prng.choice([0_u16, 0xFFFF_u16, context.prng.rand(65536).to_u16])
      when 1
        # Mutate Value bytes (e.g. byte flip or boundary values)
        if !frame.value.empty?
          pos = context.prng.rand(frame.value.size)
          frame.value[pos] ^= 0xFF_u8
        end
      when 2
        # Duplicate frame
        frames.insert(frame_idx + 1, Frame.new(frame.tag, frame.value.dup))
      else
        # Delete frame if multiple
        frames.delete_at(frame_idx) if frames.size > 1
      end

      # Re-serialize frames
      io = IO::Memory.new
      frames.each do |f|
        io.write_bytes(f.tag, IO::ByteFormat::BigEndian)
        io.write_bytes(f.value.size.to_u16, IO::ByteFormat::BigEndian)
        io.write(f.value)
      end

      buffer.replace_range(0, buffer.size, io.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def parse_frames(buffer : Buffer) : Array(Frame)
      frames = [] of Frame
      pos = 0

      while pos + 4 <= buffer.size
        tag = IO::ByteFormat::BigEndian.decode(UInt16, buffer[pos, 2])
        len = IO::ByteFormat::BigEndian.decode(UInt16, buffer[pos + 2, 2]).to_i32
        val_start = pos + 4
        val_end = val_start + len
        break if val_end > buffer.size # Truncated frame

        value_bytes = buffer[val_start, len].dup
        frames << Frame.new(tag, value_bytes)
        pos = val_end
      end

      frames
    end
  end
end
