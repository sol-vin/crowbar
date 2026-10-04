require "deque"
require "../buffer"

module Crowbar::Evolution
  # Radix/LRU Deduplication and Uniqueness Filter.
  # Tracks 64-bit FNV-1a digests of generated test cases in a bounded ring buffer.
  # Prevents redundant duplicate emissions and verifies output diversity.
  class UniquenessFilter
    property capacity : Int32
    getter seen_hashes : Set(UInt64)
    getter ring_order : Deque(UInt64)

    def initialize(@capacity : Int32 = 10_000)
      @seen_hashes = Set(UInt64).new
      @ring_order = Deque(UInt64).new(@capacity)
    end

    # Fast 64-bit FNV-1a hashing of byte slices
    def self.hash_bytes(slice : Bytes) : UInt64
      h = 0xcbf29ce484222325_u64
      slice.each do |byte|
        h ^= byte.to_u64
        h &*= 0x100000001b3_u64
      end
      h
    end

    def self.hash_buffer(buf : Buffer) : UInt64
      hash_bytes(buf.to_slice)
    end

    # Checks if a hash digest has already been recorded
    def seen?(hash : UInt64) : Bool
      @seen_hashes.includes?(hash)
    end

    def seen?(buf : Buffer | Bytes) : Bool
      slice = buf.is_a?(Buffer) ? buf.to_slice : buf
      seen?(UniquenessFilter.hash_bytes(slice))
    end

    # Adds a hash digest to the filter, evicting the oldest when at capacity
    def add(hash : UInt64) : Nil
      return if @seen_hashes.includes?(hash)

      if @ring_order.size >= @capacity
        oldest = @ring_order.shift
        @seen_hashes.delete(oldest)
      end

      @ring_order.push(hash)
      @seen_hashes.add(hash)
    end

    def add(buf : Buffer | Bytes) : UInt64
      slice = buf.is_a?(Buffer) ? buf.to_slice : buf
      h = UniquenessFilter.hash_bytes(slice)
      add(h)
      h
    end

    # Tests and records a buffer: returns true if unique (added), false if already seen
    def filter(buf : Buffer | Bytes) : Bool
      slice = buf.is_a?(Buffer) ? buf.to_slice : buf
      h = UniquenessFilter.hash_bytes(slice)
      if seen?(h)
        false
      else
        add(h)
        true
      end
    end

    def size : Int32
      @seen_hashes.size
    end

    def clear : Nil
      @seen_hashes.clear
      @ring_order.clear
    end

    # Export hashes for serialization
    def to_a : Array(UInt64)
      @ring_order.to_a
    end

    # Import hashes from serialized state
    def load_hashes(hashes : Array(UInt64)) : Nil
      clear
      hashes.last(@capacity).each do |h|
        add(h)
      end
    end
  end
end
