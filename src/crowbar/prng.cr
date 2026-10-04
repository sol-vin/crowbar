module Crowbar
  # High-performance, deterministic 64-bit pseudo-random number generator.
  # Uses Xoshiro256++ seeded via SplitMix64 for uniform statistical properties,
  # long period (2^256 - 1), and complete reproducibility across platforms.
  class PRNG
    getter seed : UInt64

    @s0 : UInt64 = 0_u64
    @s1 : UInt64 = 0_u64
    @s2 : UInt64 = 0_u64
    @s3 : UInt64 = 0_u64

    def self.default_seed : UInt64
      Random::Secure.rand(UInt64)
    end

    def initialize(@seed : UInt64 = PRNG.default_seed)
      reseed(@seed)
    end

    def seed=(new_seed : UInt64)
      @seed = new_seed
      reseed(@seed)
    end

    # Reseed the internal 256-bit state using SplitMix64
    private def reseed(s : UInt64)
      state = s
      @s0 = splitmix64(pointerof(state))
      @s1 = splitmix64(pointerof(state))
      @s2 = splitmix64(pointerof(state))
      @s3 = splitmix64(pointerof(state))

      # Ensure non-zero state
      if @s0 == 0 && @s1 == 0 && @s2 == 0 && @s3 == 0
        @s0 = 0x8a5cd789635d2dff_u64
        @s1 = 0x127a12ac98ecd92e_u64
      end
    end

    private def splitmix64(state_ptr : UInt64*) : UInt64
      z = (state_ptr.value &+= 0x9e3779b97f4a7c15_u64)
      z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9_u64
      z = (z ^ (z >> 27)) &* 0x94d049bb133111eb_u64
      z ^ (z >> 31)
    end

    # Generate next raw 64-bit unsigned integer using Xoshiro256++
    def next_u64 : UInt64
      result = rotl(@s0 &+ @s3, 23) &+ @s0
      t = @s1 << 17

      @s2 ^= @s0
      @s3 ^= @s1
      @s1 ^= @s2
      @s0 ^= @s3

      @s2 ^= t
      @s3 = rotl(@s3, 45)

      result
    end

    # Fast-forwards PRNG state by `offset` iterations
    def seek(offset : Int) : Nil
      return if offset <= 0
      offset.to_i64.times { next_u64 }
    end

    private def rotl(x : UInt64, k : Int32) : UInt64
      (x << k) | (x >> (64 - k))
    end

    # Generate next 32-bit unsigned integer
    def next_u32 : UInt32
      (next_u64 >> 32).to_u32
    end

    # Random integer in [0, max)
    def rand(max : Int) : Int32
      return 0 if max <= 1
      (next_u64 % max.to_u64).to_i32
    end

    # Random integer within inclusive range (e.g. 1..10) or exclusive range (e.g. 0...5)
    def rand(range : Range(Int32, Int32)) : Int32
      b = range.begin
      e = range.end
      e -= 1 if range.exclusive?
      return b if b >= e
      b + rand(e - b + 1)
    end

    # Random Float64 in [0.0, 1.0)
    def rand_float : Float64
      (next_u64 >> 11).to_f64 * (1.0 / 9007199254740992.0)
    end

    # Returns true with probability p (default 0.5)
    def rand_bool(prob : Float64 = 0.5) : Bool
      rand_float < prob
    end

    # Log-scale random distribution (useful for repeats, burst lengths, and byte counts)
    # Generates values from 1 up to 2^max_power with logarithmic bias towards smaller values
    def rand_log(max_power : Int32 = 14) : Int32
      power = 1
      while power < max_power && rand_bool(0.5)
        power += 1
      end
      limit = 1 << power
      [1, rand(limit)].max
    end

    # Random element from array
    def choice(array : Array(T)) : T forall T
      raise IndexError.new("Cannot pick choice from empty array") if array.empty?
      array[rand(array.size)]
    end

    def choice?(array : Array(T)) : T? forall T
      return nil if array.empty?
      array[rand(array.size)]
    end

    # Shuffle array in-place (Fisher-Yates) and return it
    def shuffle!(array : Array(T)) : Array(T) forall T
      (array.size - 1).downto(1) do |i|
        j = rand(i + 1)
        array.swap(i, j)
      end
      array
    end

    # Non-destructive shuffle
    def shuffle(array : Array(T)) : Array(T) forall T
      shuffle!(array.dup)
    end

    # Reservoir sample or simple sample
    def sample(array : Array(T), count : Int32) : Array(T) forall T
      return [] of T if count <= 0 || array.empty?
      k = [count, array.size].min
      shuffled = shuffle(array)
      shuffled[0...k]
    end
  end
end
