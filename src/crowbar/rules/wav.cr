require "./base"

module Crowbar::Rules
  # Structure-preserving rule for RIFF/WAVE audio streams.
  # Preserves the RIFF container header and WAVE subchunks (fmt , data),
  # while mutating audio format codes, channel counts, sampling rates, bit depths,
  # and PCM sample waveforms, and automatically synchronizing container and chunk sizes.
  class WAVRule < Rule
    struct Subchunk
      getter id : String
      getter offset : Int32
      property size : Int32
      getter data_offset : Int32

      def initialize(@id : String, @offset : Int32, @size : Int32, @data_offset : Int32)
      end
    end

    def name : String
      "wav"
    end

    def description : String
      "Structure-preserving RIFF/WAVE container, format chunk, and PCM audio mutation"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 12
      buffer[0, 4].to_slice == "RIFF".to_slice && buffer[8, 4].to_slice == "WAVE".to_slice
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      chunks = parse_subchunks(buffer)
      fmt_chunk = chunks.find { |c| c.id == "fmt " }
      data_chunk = chunks.find { |c| c.id == "data" }

      action = context.prng.rand(4)
      mutated = false

      case action
      when 0
        # Mutate format parameters in fmt subchunk
        if fmt_chunk && fmt_chunk.size >= 16
          mutate_fmt_chunk(fmt_chunk, buffer, context)
          mutated = true
        end
      when 1
        # Mutate PCM audio sample data in data subchunk
        if data_chunk && data_chunk.size > 0
          mutate_data_samples(data_chunk, buffer, context)
          mutated = true
        end
      when 2
        # Mutate subchunk lengths (length overflow/underflow probes)
        target = fmt_chunk || data_chunk || chunks.first?
        if target
          bad_sizes = [0_u32, 1_u32, target.size.to_u32 &+ 1_u32, 65535_u32, 4294967295_u32]
          IO::ByteFormat::LittleEndian.encode(context.prng.choice(bad_sizes), buffer[target.offset + 4, 4])
          mutated = true
        end
      else
        # Mutate arbitrary subchunk bytes or data bytes
        target = data_chunk || fmt_chunk
        if target && target.size > 0
          mutate_data_samples(target, buffer, context)
          mutated = true
        end
      end

      # Recalculate RIFF container size unless deliberately corrupted
      if mutated && action != 2
        riff_size = (buffer.size - 8).to_u32
        IO::ByteFormat::LittleEndian.encode(riff_size, buffer[4, 4])
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

    def parse_subchunks(buffer : Buffer) : Array(Subchunk)
      chunks = [] of Subchunk
      pos = 12 # Skip RIFF header (4B RIFF + 4B size + 4B WAVE)

      while pos + 8 <= buffer.size
        id_str = String.new(buffer[pos, 4].to_slice) rescue "????"
        size = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[pos + 4, 4].to_slice).to_i32 rescue 0
        data_off = pos + 8

        chunks << Subchunk.new(id_str, pos, size, data_off)

        # Chunks are padded to word boundary (even byte length)
        padded_size = size + (size % 2)
        pos += 8 + padded_size
        break if pos >= buffer.size
      end

      chunks
    end

    private def mutate_fmt_chunk(chunk : Subchunk, buffer : Buffer, context : Context)
      off = chunk.data_offset

      case context.prng.rand(4)
      when 0
        # Mutate Sample Rate (offset 4, 4 bytes LE)
        rates = [0_u32, 1_u32, 8000_u32, 11025_u32, 22050_u32, 44100_u32, 48000_u32, 96000_u32, 192000_u32, 384000_u32, 4294967295_u32]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(rates), buffer[off + 4, 4])
      when 1
        # Mutate Channel Count (offset 2, 2 bytes LE)
        channels = [0_u16, 1_u16, 2_u16, 4_u16, 6_u16, 8_u16, 255_u16, 65535_u16]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(channels), buffer[off + 2, 2])
      when 2
        # Mutate Bits Per Sample (offset 14, 2 bytes LE)
        bps = [0_u16, 4_u16, 8_u16, 12_u16, 16_u16, 24_u16, 32_u16, 64_u16, 255_u16]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(bps), buffer[off + 14, 2])
      else
        # Mutate Audio Format code (offset 0, 2 bytes LE)
        # 1 = PCM, 3 = IEEE Float, 6 = A-law, 7 = mu-law, 65534 = Extensible
        codes = [0_u16, 1_u16, 2_u16, 3_u16, 6_u16, 7_u16, 65534_u16, 65535_u16]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(codes), buffer[off, 2])
      end
    end

    private def mutate_data_samples(chunk : Subchunk, buffer : Buffer, context : Context)
      len = [chunk.size, buffer.size - chunk.data_offset].min
      return if len <= 0

      mut_count = [len, context.prng.rand(1..8)].min
      mut_count.times do
        idx = chunk.data_offset + context.prng.rand(len)
        buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
      end
    end
  end
end
