module Crowbar::Selectors
  # Selects header prefix bytes (or inverted: everything but header)
  class Header < Selector
    getter length : Int32
    getter invert : Bool

    def initialize(@length : Int32, @invert : Bool = false, weight : Float64 = 1.0)
      super(weight)
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) if buffer.empty?
      split_point = [0, [@length, buffer.size].min].max

      if @invert
        split_point < buffer.size ? [{split_point, buffer.size}] : [] of Tuple(Int32, Int32)
      else
        split_point > 0 ? [{0, split_point}] : [] of Tuple(Int32, Int32)
      end
    end
  end

  # Selects footer suffix bytes (or inverted: everything but footer)
  class Footer < Selector
    getter length : Int32
    getter invert : Bool

    def initialize(@length : Int32, @invert : Bool = false, weight : Float64 = 1.0)
      super(weight)
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) if buffer.empty?
      split_point = [0, buffer.size - @length].max

      if @invert
        split_point > 0 ? [{0, split_point}] : [] of Tuple(Int32, Int32)
      else
        split_point < buffer.size ? [{split_point, buffer.size}] : [] of Tuple(Int32, Int32)
      end
    end
  end
end
