require "./base"

module Crowbar::Mutators
  abstract class TreeMutator < Mutator
    DELIMITERS = [
      {0x28_u8, 0x29_u8}, # ()
      {0x5B_u8, 0x5D_u8}, # []
      {0x7B_u8, 0x7D_u8}, # {}
      {0x3C_u8, 0x3E_u8}, # <>
      {0x22_u8, 0x22_u8}, # ""
      {0x27_u8, 0x27_u8}, # ''
    ]

    protected def find_all_pairs(buffer : Buffer) : Array(Tuple(Int32, Int32))
      all_pairs = [] of Tuple(Int32, Int32)
      DELIMITERS.each do |(open_b, close_b)|
        pairs = buffer.find_delimiter_pairs(open_b, close_b)
        all_pairs.concat(pairs)
      end
      all_pairs
    end
  end

  # Deletes a balanced delimited tree node
  class TreeDelete < TreeMutator
    def name : String
      "td"
    end

    def description : String
      "Delete a balanced delimited node (), [], {}, <>, \"\", ''"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      pairs = find_all_pairs(buffer)
      return {false, -1} if pairs.empty?

      start_pos, end_pos = context.prng.choice(pairs)
      length = end_pos - start_pos

      buffer.delete_range(start_pos, length)
      context.record_mutation(name, {start_pos, end_pos})
      {true, 1}
    end
  end

  # Duplicates a balanced delimited tree node
  class TreeDuplicate < TreeMutator
    def name : String
      "tr2"
    end

    def description : String
      "Duplicate a balanced delimited node"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      pairs = find_all_pairs(buffer)
      return {false, -1} if pairs.empty?

      start_pos, end_pos = context.prng.choice(pairs)
      node_bytes = Array.new(end_pos - start_pos) { |i| buffer[start_pos + i] }

      buffer.insert(end_pos, node_bytes)
      context.record_mutation(name, {start_pos, end_pos + node_bytes.size})
      {true, 1}
    end
  end

  # Swaps two balanced delimited tree nodes
  class TreeSwap < TreeMutator
    def name : String
      "ts1"
    end

    def description : String
      "Swap two balanced delimited nodes"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      pairs = find_all_pairs(buffer)
      return {false, -1} if pairs.size < 2

      # Find two non-overlapping pairs
      p1 = context.prng.choice(pairs)
      non_overlapping = pairs.reject do |p|
        # Check overlap
        (p[0] >= p1[0] && p[0] < p1[1]) || (p[1] > p1[0] && p[1] <= p1[1]) ||
          (p1[0] >= p[0] && p1[0] < p[1]) || (p1[1] > p[0] && p1[1] <= p[1])
      end
      return {false, 0} if non_overlapping.empty?

      p2 = context.prng.choice(non_overlapping)

      s1, e1 = p1
      s2, e2 = p2
      s1, s2, e1, e2 = s2, s1, e2, e1 if s1 > s2

      n1 = Array.new(e1 - s1) { |i| buffer[s1 + i] }
      n2 = Array.new(e2 - s2) { |i| buffer[s2 + i] }

      buffer.replace_range(s2, e2 - s2, n1)
      buffer.replace_range(s1, e1 - s1, n2)

      context.record_mutation(name, {s1, s2 + n1.size})
      {true, 1}
    end
  end

  # Repeats a tree node multiple times (tree stutter)
  class TreeStutter < TreeMutator
    def name : String
      "tr"
    end

    def description : String
      "Repeat a balanced delimited node multiple times"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      pairs = find_all_pairs(buffer)
      return {false, -1} if pairs.empty?

      start_pos, end_pos = context.prng.choice(pairs)
      node_bytes = Array.new(end_pos - start_pos) { |i| buffer[start_pos + i] }
      count = context.prng.rand_log(6) # 1 to 64 repeats

      insert_pos = end_pos
      count.times do
        buffer.insert(insert_pos, node_bytes)
        insert_pos += node_bytes.size
      end

      context.record_mutation(name, {start_pos, insert_pos})
      {true, 1}
    end
  end
end
