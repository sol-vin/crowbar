require "./base"

module Crowbar::Mutators
  # Repeats/stutters a sub-sequence of bytes
  class SequenceRepeat < Mutator
    def name : String
      "sr"
    end

    def description : String
      "Repeat a sequence of bytes"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len < 2

      seq_len = context.prng.rand(1..[len, 64].min)
      start_pos = b + context.prng.rand(len - seq_len + 1)
      chunk = Array.new(seq_len) { |i| buffer[start_pos + i] }

      reps = context.prng.rand_log(8) # 1 to 256 repeats
      insert_pos = start_pos + seq_len

      reps.times do
        buffer.insert(insert_pos, chunk)
        insert_pos += seq_len
      end

      context.record_mutation(name, {start_pos, insert_pos})
      {true, 0}
    end
  end

  # Deletes a sub-sequence of bytes
  class SequenceDelete < Mutator
    def name : String
      "sd"
    end

    def description : String
      "Delete a sequence of bytes"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len < 2

      seq_len = context.prng.rand(1..[len - 1, 128].min)
      start_pos = b + context.prng.rand(len - seq_len + 1)

      buffer.delete_range(start_pos, seq_len)
      context.record_mutation(name, {start_pos, start_pos + seq_len})
      {true, 0}
    end
  end

  # Swaps two non-overlapping byte sequences
  class SequenceSwap < Mutator
    def name : String
      "ss"
    end

    def description : String
      "Swap two disjoint sequences of bytes"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len < 4

      chunk_size = context.prng.rand(1..[len // 3, 32].min)
      pos1 = b + context.prng.rand(len - (chunk_size * 2) + 1)
      pos2 = pos1 + chunk_size + context.prng.rand(len - pos1 - (chunk_size * 2) + 1)

      chunk_size.times do |i|
        v1 = buffer[pos1 + i]
        v2 = buffer[pos2 + i]
        buffer[pos1 + i] = v2
        buffer[pos2 + i] = v1
      end

      context.record_mutation(name, {pos1, pos2 + chunk_size})
      {true, 0}
    end
  end
end
