require "../buffer"

module Crowbar
  # Selectors isolate and target specific regions of a buffer for mutation.
  abstract class Selector
    property weight : Float64 = 1.0

    def initialize(@weight : Float64 = 1.0)
    end

    # Returns an array of target ranges {start_index, end_index_exclusive}
    abstract def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
  end

  module Selectors
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

    # Selects regions matching a regular expression (with capture group support)
    class Regex < Selector
      getter pattern : ::Regex
      getter group : Int32

      def initialize(@pattern : ::Regex, @group : Int32 = 0, weight : Float64 = 1.0)
        super(weight)
      end

      def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
        str = buffer.to_raw_s
        matches = [] of Tuple(Int32, Int32)

        str.scan(@pattern) do |match|
          if @group == 0
            b = match.byte_begin
            e = match.byte_end
            matches << {b, e}
          elsif match.size > @group
            b = match.byte_begin(@group)
            e = match.byte_end(@group)
            matches << {b, e} if b >= 0 && e >= b
          end
        end
        matches
      end
    end

    # Selects matched delimiter blocks (e.g. quotes or brackets)
    class Delimiters < Selector
      getter open_byte : UInt8
      getter close_byte : UInt8

      def initialize(@open_byte : UInt8, @close_byte : UInt8, weight : Float64 = 1.0)
        super(weight)
      end

      def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
        buffer.find_delimiter_pairs(@open_byte, @close_byte)
      end
    end
  end
end
