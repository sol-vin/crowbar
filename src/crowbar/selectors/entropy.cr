module Crowbar::Selectors
  # Selects regions based on Shannon information entropy:
  # - :high entropy (>= threshold, default 6.5 bits/byte): identifies compressed, encrypted, or random payload chunks.
  # - :low entropy (<= threshold, default 2.5 bits/byte): identifies repetitive padding, null blocks, or tabular space runs.
  class Entropy < Selector
    enum Mode
      High
      Low
    end

    getter mode : Mode
    getter threshold : Float64
    getter window_size : Int32

    def initialize(
      mode : Mode | Symbol = :high,
      threshold : Float64? = nil,
      @window_size : Int32 = 32,
      weight : Float64 = 1.0,
    )
      super(weight)
      @mode = case mode
              when Mode then mode
              when :low then Mode::Low
              else           Mode::High
              end

      @threshold = threshold || (@mode == Mode::High ? 6.5 : 2.5)
      raise ArgumentError.new("window_size must be >= 4") if @window_size < 4
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) if buffer.size < @window_size

      matches = [] of Tuple(Int32, Int32)
      pos = 0
      step = [@window_size // 2, 1].max

      while pos + @window_size <= buffer.size
        window_bytes = buffer[pos, @window_size]
        entropy = calculate_entropy(window_bytes)

        matched = case @mode
                  when Mode::High then entropy >= @threshold
                  when Mode::Low  then entropy <= @threshold
                  end

        if matched
          matches << {pos, pos + @window_size}
        end

        pos += step
      end

      # Merge overlapping matched windows using RangeUtils
      RangeUtils.normalize(matches)
    end

    # Calculates Shannon entropy in bits per byte [0.0 .. 8.0]
    def self.calculate_entropy(bytes : Bytes) : Float64
      return 0.0 if bytes.empty?

      counts = StaticArray(Int32, 256).new(0)
      bytes.each { |b| counts[b.to_i] += 1 }

      total = bytes.size.to_f64
      entropy = 0.0

      counts.each do |c|
        if c > 0
          p = c.to_f64 / total
          entropy -= p * (Math.log(p) / Math.log(2.0))
        end
      end

      entropy
    end

    private def calculate_entropy(bytes : Bytes) : Float64
      self.class.calculate_entropy(bytes)
    end
  end
end
