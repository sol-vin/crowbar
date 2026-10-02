module Crowbar::Selectors
  # Selects a static byte index range (e.g. 0...16 or 20..)
  class ByteRange < Selector
    getter begin_index : Int32
    getter end_index : Int32?
    getter? exclusive : Bool

    def initialize(@begin_index : Int32, @end_index : Int32?, @exclusive : Bool = false, weight : Float64 = 1.0)
      super(weight)
    end

    def self.new(range : Range(B, E), weight : Float64 = 1.0) forall B, E
      b = range.begin.to_i32
      end_val = range.end
      e = end_val ? end_val.to_i32 : nil
      new(b, e, range.exclusive?, weight)
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) if buffer.empty?

      b = [0, [@begin_index, buffer.size].min].max
      e = if val = @end_index
            val -= 1 if @exclusive
            [b, [val + 1, buffer.size].min].max
          else
            buffer.size
          end

      return [] of Tuple(Int32, Int32) if b >= e
      [{b, e}]
    end
  end
end
