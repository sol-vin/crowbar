require "./base"

module Crowbar::Mutators
  # Flips a contiguous sequence of 2 to 32 bits across byte boundaries (burst transmission fault)
  class BitFlipRun < Mutator
    def name : String
      "bfr"
    end

    def description : String
      "Flip a contiguous run of 2 to 32 bits across byte boundaries"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      total_bits = len * 8
      run_length = context.prng.rand(2..[32, total_bits].min)
      bit_start = (b * 8) + context.prng.rand(total_bits - run_length + 1)

      (0...run_length).each do |i|
        bit_idx = bit_start + i
        byte_idx = bit_idx // 8
        bit_offset = bit_idx % 8
        buffer[byte_idx] ^= (1_u8 << bit_offset)
      end

      affected_start = bit_start // 8
      affected_end = [(bit_start + run_length + 7) // 8, buffer.size].min
      context.record_mutation(name, {affected_start, affected_end})
      {true, 0}
    end
  end

  # Slides a single inverted bit systematically or across a chosen window (1-bit walk)
  class WalkingBit < Mutator
    def name : String
      "wb"
    end

    def description : String
      "Slide an inverted single bit through target byte window"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len)
      bit = context.prng.rand(8)

      buffer[pos] ^= (1_u8 << bit)
      context.record_mutation(name, {pos, pos + 1})
      {true, 0}
    end
  end
end
