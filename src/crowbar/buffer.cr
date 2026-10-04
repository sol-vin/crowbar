module Crowbar
  # Binary-safe byte buffer container for non-destructive and in-place transformations.
  # Handles raw bytes, arbitrary non-UTF-8 binaries, and provides slicing/splicing helpers.
  class Buffer
    getter bytes : Array(UInt8)

    def initialize(initial_bytes : Bytes | Array(UInt8) | String = Bytes.empty)
      case initial_bytes
      when Bytes
        @bytes = initial_bytes.to_a
      when Array(UInt8)
        @bytes = initial_bytes.dup
      when String
        @bytes = initial_bytes.to_slice.to_a
      else
        @bytes = [] of UInt8
      end
    end

    def self.from_io(io : IO, limit : Int32? = nil) : self
      slice = if lim = limit
                buf = Bytes.new(lim)
                read_bytes = io.read(buf)
                buf[0, read_bytes]
              else
                io.getb_to_end
              end
      new(slice)
    end

    def size : Int32
      @bytes.size
    end

    def empty? : Bool
      @bytes.empty?
    end

    def [](index : Int32) : UInt8
      @bytes[index]
    end

    def []?(index : Int32) : UInt8?
      @bytes[index]?
    end

    def []=(index : Int32, value : UInt8)
      @bytes[index] = value
    end

    def [](range : Range(B, E)) : Bytes forall B, E
      b_val = range.begin
      e_val = range.end

      b = b_val ? b_val.to_i32 : 0
      b = [0, [b, size].min].max

      e = if e_val
            val = e_val.to_i32
            val -= 1 if range.exclusive?
            [0, [val, size - 1].min].max
          else
            [0, size - 1].max
          end

      return Bytes.empty if b > e || empty?
      to_slice[b..e]
    end

    def [](start : Int32, count : Int32) : Bytes
      return Bytes.empty if start < 0 || count <= 0 || start >= size
      actual_count = [count, size - start].min
      to_slice[start, actual_count]
    end

    def to_slice : Bytes
      Slice(UInt8).new(@bytes.to_unsafe, @bytes.size)
    end

    def to_s(io : IO) : Nil
      io.write(to_slice)
    end

    def to_s : String
      String.new(to_slice)
    rescue
      # Safe fallback for non-UTF8 binary data
      String.build do |str|
        @bytes.each do |b|
          if b >= 32 && b <= 126
            str << b.unsafe_chr
          else
            str << "\\x"
            str << b.to_s(16, upcase: true).rjust(2, '0')
          end
        end
      end
    end

    def to_raw_s : String
      # Lossy or byte-preserved string
      String.new(to_slice)
    rescue
      @bytes.map { |b| b < 128 ? b.unsafe_chr : '?' }.join
    end

    def clone : Buffer
      Buffer.new(@bytes.dup)
    end

    # Insert a single byte at position
    def insert(pos : Int32, byte : UInt8)
      pos = [0, [pos, size].min].max
      @bytes.insert(pos, byte)
    end

    # Insert a byte slice at position
    def insert(pos : Int32, slice : Bytes | Array(UInt8))
      pos = [0, [pos, size].min].max
      slice.each_with_index do |b, idx|
        @bytes.insert(pos + idx, b)
      end
    end

    # Delete single byte at position
    def delete_at(pos : Int32) : UInt8?
      return nil if pos < 0 || pos >= size
      @bytes.delete_at(pos)
    end

    # Delete a contiguous range of bytes
    def delete_range(start : Int32, length : Int32)
      return if start < 0 || start >= size || length <= 0
      actual_len = [length, size - start].min
      actual_len.times { @bytes.delete_at(start) }
    end

    # Replace a slice with another slice
    def replace_range(start : Int32, length : Int32, replacement : Bytes | Array(UInt8))
      delete_range(start, length)
      insert(start, replacement)
    end

    # Clears all bytes in buffer
    def clear : Nil
      @bytes.clear
    end

    # Appends bytes to the buffer
    def concat(slice : Bytes | Array(UInt8)) : Nil
      slice.each { |b| @bytes << b }
    end

    # Searches for a needle sequence starting at offset
    def index(needle : Bytes | Array(UInt8) | Buffer, offset : Int32 = 0) : Int32?
      n_slice = needle.is_a?(Buffer) ? needle.to_slice : (needle.is_a?(Array(UInt8)) ? needle.to_slice : needle)
      return nil if n_slice.empty? || offset >= size
      return nil if size - offset < n_slice.size

      start_pos = [0, offset].max
      max_idx = size - n_slice.size
      start_pos.upto(max_idx) do |i|
        match = true
        n_slice.each_with_index do |b, j|
          if @bytes[i + j] != b
            match = false
            break
          end
        end
        return i if match
      end
      nil
    end

    # Swaps two equal-length ranges of bytes in-place
    def swap_ranges(pos1 : Int32, len : Int32, pos2 : Int32, len2 : Int32 = len) : Nil
      return if pos1 < 0 || pos2 < 0
      actual_len = [len, len2, size - pos1, size - pos2].min
      return if actual_len <= 0

      actual_len.times do |i|
        v1 = @bytes[pos1 + i]
        v2 = @bytes[pos2 + i]
        @bytes[pos1 + i] = v2
        @bytes[pos2 + i] = v1
      end
    end

    # Find line ranges (0-indexed [start, end_exclusive])
    def lines : Array(Tuple(Int32, Int32))
      ranges = [] of Tuple(Int32, Int32)
      return ranges if empty?

      line_start = 0
      @bytes.each_with_index do |b, i|
        if b == 0x0A_u8 # '\n'
          ranges << {line_start, i + 1}
          line_start = i + 1
        end
      end
      if line_start < size
        ranges << {line_start, size}
      end
      ranges
    end

    # Find balanced delimiter pairs like (), [], {}, <>, "", ''
    def find_delimiter_pairs(open_byte : UInt8, close_byte : UInt8) : Array(Tuple(Int32, Int32))
      pairs = [] of Tuple(Int32, Int32)
      return pairs if empty?

      if open_byte == close_byte
        # Quotation pair search
        start_idx = nil
        escaped = false
        @bytes.each_with_index do |b, i|
          if b == 0x5C_u8 # '\'
            escaped = !escaped
            next
          end
          if b == open_byte && !escaped
            if s = start_idx
              pairs << {s, i + 1}
              start_idx = nil
            else
              start_idx = i
            end
          end
          escaped = false
        end
      else
        # Nested bracket pair search
        stack = [] of Int32
        @bytes.each_with_index do |b, i|
          if b == open_byte
            stack << i
          elsif b == close_byte && !stack.empty?
            s = stack.pop
            pairs << {s, i + 1}
          end
        end
      end
      pairs
    end

    # Check if buffer appears to be mostly text
    def text? : Bool
      return true if empty?
      sample_size = [size, 512].min
      printable_count = 0
      sample_size.times do |i|
        b = @bytes[i]
        printable_count += 1 if (b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13
      end
      (printable_count / sample_size.to_f) > 0.85
    end
  end
end
