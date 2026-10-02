require "./base"

module Crowbar::Mutators
  # Deletes a random byte from the buffer
  class ByteDrop < Mutator
    def name : String
      "bd"
    end

    def description : String
      "Drop a single random byte"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len)
      buffer.delete_at(pos)
      context.record_mutation(name, {pos, pos + 1})
      {true, 0}
    end
  end

  # Inverts (flips) random bits in a byte
  class ByteFlip < Mutator
    def name : String
      "bf"
    end

    def description : String
      "Flip 1-4 bits in a random byte"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len)
      bit_count = context.prng.rand(1..4)
      mask = 0_u8
      bit_count.times do
        mask |= (1_u8 << context.prng.rand(8))
      end

      buffer[pos] ^= mask
      context.record_mutation(name, {pos, pos + 1})
      {true, 0}
    end
  end

  # Inserts a random byte at a random position
  class ByteInsert < Mutator
    def name : String
      "bi"
    end

    def description : String
      "Insert a random byte at a random position"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      pos = b + (len > 0 ? context.prng.rand(len + 1) : 0)

      byte = context.prng.rand(256).to_u8
      buffer.insert(pos, byte)
      context.record_mutation(name, {pos, pos + 1})
      {true, 0}
    end
  end

  # Repeats a byte multiple times using a logarithmic distribution
  class ByteRepeat < Mutator
    def name : String
      "br"
    end

    def description : String
      "Repeat a byte multiple times"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len)
      byte = buffer[pos]
      count = context.prng.rand_log(10) # 1 to 1024 repetitions
      repeated = Bytes.new(count, byte)

      buffer.insert(pos + 1, repeated)
      context.record_mutation(name, {pos, pos + count + 1})
      {true, 0}
    end
  end

  # Permutes/shuffles adjacent bytes
  class BytePermute < Mutator
    def name : String
      "bp"
    end

    def description : String
      "Permute a contiguous window of adjacent bytes"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len < 2

      window_size = context.prng.rand(2..[len, 16].min)
      start_pos = b + context.prng.rand(len - window_size + 1)

      window_slice = Array.new(window_size) { |i| buffer[start_pos + i] }
      context.prng.shuffle!(window_slice)

      window_slice.each_with_index do |val, idx|
        buffer[start_pos + idx] = val
      end

      context.record_mutation(name, {start_pos, start_pos + window_size})
      {true, 0}
    end
  end

  # Increments or decrements a byte value mod 256
  class ByteIncDec < Mutator
    def name : String
      "bei"
    end

    def description : String
      "Increment or decrement a byte value mod 256"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len)
      delta = context.prng.rand_bool ? 1_u8 : 255_u8 # +1 or -1 mod 256
      buffer[pos] &+= delta

      context.record_mutation(name, {pos, pos + 1})
      {true, 0}
    end
  end

  # Replaces a byte with a uniform random byte
  class ByteRandom < Mutator
    def name : String
      "ber"
    end

    def description : String
      "Replace a byte with a uniform random value"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len)
      buffer[pos] = context.prng.rand(256).to_u8

      context.record_mutation(name, {pos, pos + 1})
      {true, 0}
    end
  end
end
