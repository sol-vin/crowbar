require "./base"

module Crowbar::Mutators
  # Base for line-aware mutators
  abstract class LineMutator < Mutator
    protected def get_lines(buffer : Buffer) : Array(Tuple(Int32, Int32))
      buffer.lines
    end
  end

  # Deletes a line from a line-structured input
  class LineDelete < LineMutator
    def name : String
      "ld"
    end

    def description : String
      "Delete a line in text-based data"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      lines = get_lines(buffer)
      return {false, -1} if lines.size < 2

      idx = context.prng.rand(lines.size)
      start_pos, end_pos = lines[idx]
      length = end_pos - start_pos

      buffer.delete_range(start_pos, length)
      context.record_mutation(name, {start_pos, end_pos})
      {true, 1}
    end
  end

  # Duplicates a line closeby
  class LineDuplicate < LineMutator
    def name : String
      "lr2"
    end

    def description : String
      "Duplicate a line in text-based data"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      lines = get_lines(buffer)
      return {false, -1} if lines.empty?

      idx = context.prng.rand(lines.size)
      start_pos, end_pos = lines[idx]
      line_bytes = Array.new(end_pos - start_pos) { |i| buffer[start_pos + i] }

      buffer.insert(end_pos, line_bytes)
      context.record_mutation(name, {start_pos, end_pos + line_bytes.size})
      {true, 1}
    end
  end

  # Swaps two lines in text data
  class LineSwap < LineMutator
    def name : String
      "ls"
    end

    def description : String
      "Swap two lines in text-based data"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      lines = get_lines(buffer)
      return {false, -1} if lines.size < 2

      idx1 = context.prng.rand(lines.size)
      idx2 = context.prng.rand(lines.size)
      return {false, 0} if idx1 == idx2

      # Sort indices so we replace from right to left to keep offsets valid
      idx1, idx2 = idx2, idx1 if idx1 > idx2
      s1, e1 = lines[idx1]
      s2, e2 = lines[idx2]

      l1 = Array.new(e1 - s1) { |i| buffer[s1 + i] }
      l2 = Array.new(e2 - s2) { |i| buffer[s2 + i] }

      # Replace higher index first
      buffer.replace_range(s2, e2 - s2, l1)
      buffer.replace_range(s1, e1 - s1, l2)

      context.record_mutation(name, {s1, s2 + l1.size})
      {true, 1}
    end
  end

  # Permutes/shuffles a block of lines
  class LinePermute < LineMutator
    def name : String
      "lp"
    end

    def description : String
      "Permute a contiguous group of lines"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      lines = get_lines(buffer)
      return {false, -1} if lines.size < 3

      count = context.prng.rand(2..[lines.size, 8].min)
      start_line_idx = context.prng.rand(lines.size - count + 1)

      extracted_lines = (0...count).map do |i|
        s, e = lines[start_line_idx + i]
        Array.new(e - s) { |j| buffer[s + j] }
      end

      shuffled = context.prng.shuffle(extracted_lines)
      flat_shuffled = shuffled.flatten

      total_start, _ = lines[start_line_idx]
      _, total_end = lines[start_line_idx + count - 1]

      buffer.replace_range(total_start, total_end - total_start, flat_shuffled)
      context.record_mutation(name, {total_start, total_start + flat_shuffled.size})
      {true, 1}
    end
  end
end
