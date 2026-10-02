require "./base"

module Crowbar::Mutators
  # Injects null, space, or alignment padding to align with binary boundaries (4, 8, 16, 64, 512 bytes)
  class PaddingMutator < Mutator
    ALIGNMENTS = [4, 8, 16, 32, 64, 128, 512]

    def name : String
      "pad"
    end

    def description : String
      "Inject null, whitespace, or alignment padding"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b

      pad_byte = context.prng.choice([0x00_u8, 0x20_u8, 0xFF_u8])
      align = context.prng.choice(ALIGNMENTS)
      remainder = buffer.size % align
      pad_count = remainder == 0 ? align : (align - remainder)

      pad_bytes = Bytes.new(pad_count, pad_byte)
      pos = context.prng.rand_bool ? buffer.size : (b + (len > 0 ? context.prng.rand(len + 1) : 0))

      buffer.insert(pos, pad_bytes)
      context.record_mutation(name, {pos, pos + pad_count})
      {true, 0}
    end
  end

  # Truncates buffer at logical boundaries (line breaks, delimiters) or random offsets
  class TruncationMutator < Mutator
    def name : String
      "trunc"
    end

    def description : String
      "Truncate buffer at logical line, delimiter, or random offset"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      return {false, -1} if buffer.size <= 1

      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 1

      trunc_point = case context.prng.rand(3)
                    when 0 # Truncate at random newline
                      nl = nil
                      (b...e).each do |i|
                        if buffer[i] == 0x0A_u8
                          nl = i + 1
                          break
                        end
                      end
                      nl ? nl : (b + len // 2)
                    when 1 # Truncate at delimiter (;,:,/,|)
                      delim = nil
                      (b...e).each do |i|
                        byte = buffer[i]
                        if byte == 0x3B_u8 || byte == 0x2C_u8 || byte == 0x3A_u8 || byte == 0x2F_u8 || byte == 0x7C_u8
                          delim = i
                          break
                        end
                      end
                      delim ? delim : (b + len // 2)
                    else # Truncate at random position
                      b + context.prng.rand(1...len)
                    end

      trunc_point = [1, [trunc_point, buffer.size - 1].min].max
      delete_count = buffer.size - trunc_point

      buffer.delete_range(trunc_point, delete_count)
      context.record_mutation(name, {trunc_point, buffer.size})
      {true, 0}
    end
  end
end
