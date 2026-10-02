module Crowbar::Selectors
  # Selects periodic byte slices at regular intervals (e.g. every 4th byte, alternating words, audio samples).
  class Stride < Selector
    getter step : Int32
    getter offset : Int32
    getter length : Int32

    def initialize(@step : Int32, @offset : Int32 = 0, @length : Int32 = 1, weight : Float64 = 1.0)
      super(weight)
      raise ArgumentError.new("Step must be positive") if @step <= 0
      raise ArgumentError.new("Length must be positive") if @length <= 0
      raise ArgumentError.new("Offset cannot be negative") if @offset < 0
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) if buffer.empty? || @offset >= buffer.size

      matches = [] of Tuple(Int32, Int32)
      pos = @offset

      while pos < buffer.size
        s = pos
        e = [pos + @length, buffer.size].min
        matches << {s, e} if s < e
        pos += @step
      end

      matches
    end
  end
end
