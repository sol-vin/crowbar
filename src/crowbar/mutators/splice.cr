require "./base"

module Crowbar::Mutators
  # Alignment-based Markov sequence splicing and motif crossover.
  # Inspired by Radamsa's 'fuse' ('ft' for intra-stream motif jumps and 'fn' for inter-sample splicing).
  # Preserves syntactical transitions by cutting and reconnecting streams at matching n-gram prefixes.
  class Splice < Mutator
    def name : String
      "splice"
    end

    def aliases : Array(String)
      ["fuse", "ft", "fn"]
    end

    def description : String
      "Markov alignment sequence splicing across samples and intra-stream motifs"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b

      # 1. Inter-sample splicing (Radamsa 'fn') if secondary samples exist
      if !context.secondary_samples.empty? && (context.prng.rand_bool(0.6) || len < 4)
        other = context.prng.choice(context.secondary_samples)
        if other.size >= 2
          return mutate_inter_sample(context, buffer, other, b, e)
        end
      end

      # 2. Intra-stream motif alignment & Markov jump (Radamsa 'ft')
      return {false, -1} if len < 4
      mutate_intra_stream(context, buffer, b, e)
    end

    # Splice buffer with an external candidate/sample at an aligned n-gram or crossover point
    private def mutate_inter_sample(
      context : Context,
      buffer : Buffer,
      other : Buffer,
      b : Int32,
      e : Int32,
    ) : Tuple(Bool, Int32)
      k_sizes = [4, 3, 2]
      common_k = 0
      pos_buf = -1
      pos_other = -1

      # Try to find a matching k-mer
      k_sizes.each do |k|
        break if common_k > 0
        max_start = (e - k)
        next if max_start < b

        # Sample up to 6 positions in buffer
        attempts = [6, max_start - b + 1].min
        attempts.times do
          cand_pos = b + context.prng.rand(max_start - b + 1)
          kmer = buffer[cand_pos, k]

          # Look for kmer in other buffer
          match_idx = other.index(kmer)
          if match_idx && match_idx >= 0
            common_k = k
            pos_buf = cand_pos
            pos_other = match_idx
            break
          end
        end
      end

      if common_k > 0 && pos_buf >= 0 && pos_other >= 0
        # Aligned splice: prefix up to pos_buf + other from pos_other
        prefix = buffer[0...pos_buf]
        suffix = other[pos_other...other.size]
        new_bytes = Bytes.new(prefix.size + suffix.size)
        prefix.copy_to(new_bytes.to_slice[0, prefix.size])
        suffix.copy_to(new_bytes.to_slice[prefix.size, suffix.size])

        buffer.clear
        buffer.concat(new_bytes)
        context.record_mutation(name, {pos_buf, [pos_buf + common_k, buffer.size].min})
        {true, 1}
      else
        # Unaligned crossover fallback
        cut_buf = b + context.prng.rand([1, e - b].max)
        cut_other = context.prng.rand(other.size)

        prefix = buffer[0...cut_buf]
        suffix = other[cut_other...other.size]
        new_bytes = Bytes.new(prefix.size + suffix.size)
        prefix.copy_to(new_bytes.to_slice[0, prefix.size])
        suffix.copy_to(new_bytes.to_slice[prefix.size, suffix.size])

        buffer.clear
        buffer.concat(new_bytes)
        context.record_mutation(name, {b, e})
        {true, 0}
      end
    end

    # Self-align motifs within the buffer for Markov repetition or loop deletion
    private def mutate_intra_stream(
      context : Context,
      buffer : Buffer,
      b : Int32,
      e : Int32,
    ) : Tuple(Bool, Int32)
      len = e - b
      k = [len // 4, [2, context.prng.rand(2..4)].max].min
      k = 2 if k < 2

      # Sample candidate positions to find repeated k-mer motifs
      p1 = -1
      p2 = -1
      max_start = e - k

      if max_start > b
        samples = [8, max_start - b].min
        samples.times do
          cand_p1 = b + context.prng.rand(max_start - b)
          kmer = buffer[cand_p1, k]

          # Search for repeat of kmer in the rest of range
          search_start = cand_p1 + k
          if search_start <= max_start
            found_rel = buffer.index(kmer, offset: search_start)
            if found_rel && found_rel <= max_start
              p1 = cand_p1
              p2 = found_rel
              break
            end
          end
        end
      end

      if p1 >= 0 && p2 > p1
        action = context.prng.rand(3)
        case action
        when 0
          # Markov loop deletion: remove segment between identical prefixes
          buffer.delete_range(p1, p2 - p1)
          context.record_mutation(name, {p1, p1 + k})
          {true, 1}
        when 1
          # Markov loop duplication: repeat segment between aligned motifs
          seg = buffer[p1, p2 - p1]
          buffer.insert(p2, seg)
          context.record_mutation(name, {p2, p2 + seg.size})
          {true, 1}
        else
          # Markov crossover swap
          seg_len = [k * 2, p2 - p1].min
          buffer.swap_ranges(p1, seg_len, p2, seg_len)
          context.record_mutation(name, {p1, p2 + seg_len})
          {true, 1}
        end
      else
        # Fallback: swap two adjacent chunks
        mid = b + (len // 2)
        chunk_len = [context.prng.rand(1..[4, len // 2].max), 1].max
        p_left = b + context.prng.rand([1, mid - b - chunk_len + 1].max)
        p_right = mid + context.prng.rand([1, e - mid - chunk_len + 1].max)

        if p_left + chunk_len <= buffer.size && p_right + chunk_len <= buffer.size
          buffer.swap_ranges(p_left, chunk_len, p_right, chunk_len)
          context.record_mutation(name, {p_left, p_right + chunk_len})
          {true, 0}
        else
          {false, -1}
        end
      end
    end
  end
end
