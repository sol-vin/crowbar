require "../buffer"

module Crowbar
  # Helper algorithms for normalizing, intersecting, unioning, and inverting byte index ranges.
  module RangeUtils
    def self.normalize(ranges : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
      return ranges if ranges.size <= 1
      valid = ranges.select { |(s, e)| s < e }
      return [] of Tuple(Int32, Int32) if valid.empty?

      sorted = valid.sort_by { |(s, e)| {s, e} }
      merged = [] of Tuple(Int32, Int32)
      cur_s, cur_e = sorted.first

      sorted[1..].each do |(s, e)|
        if s <= cur_e
          cur_e = [cur_e, e].max
        else
          merged << {cur_s, cur_e}
          cur_s, cur_e = s, e
        end
      end
      merged << {cur_s, cur_e}
      merged
    end

    def self.intersect(ranges_a : Array(Tuple(Int32, Int32)), ranges_b : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
      norm_a = normalize(ranges_a)
      norm_b = normalize(ranges_b)
      result = [] of Tuple(Int32, Int32)

      norm_a.each do |(sa, ea)|
        norm_b.each do |(sb, eb)|
          s = [sa, sb].max
          e = [ea, eb].min
          result << {s, e} if s < e
        end
      end
      normalize(result)
    end

    def self.union(ranges_a : Array(Tuple(Int32, Int32)), ranges_b : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
      normalize(ranges_a + ranges_b)
    end

    def self.invert(ranges : Array(Tuple(Int32, Int32)), total_size : Int32) : Array(Tuple(Int32, Int32))
      return [{0, total_size}] if ranges.empty? && total_size > 0
      norm = normalize(ranges)
      result = [] of Tuple(Int32, Int32)
      cur = 0

      norm.each do |(s, e)|
        s_clamped = [0, [s, total_size].min].max
        e_clamped = [0, [e, total_size].min].max
        result << {cur, s_clamped} if s_clamped > cur
        cur = [cur, e_clamped].max
      end
      result << {cur, total_size} if cur < total_size
      result
    end
  end

  # Selectors isolate and target specific regions of a buffer for mutation.
  abstract class Selector
    property weight : Float64 = 1.0

    def initialize(@weight : Float64 = 1.0)
    end

    # Returns an array of target ranges {start_index, end_index_exclusive}
    abstract def select(buffer : Buffer) : Array(Tuple(Int32, Int32))

    # Intersection combinator: targets only byte regions selected by BOTH selectors
    def &(other : Selector) : Selector
      Selectors::And.new(self, other)
    end

    # Union combinator: targets regions selected by EITHER selector
    def |(other : Selector) : Selector
      Selectors::Or.new(self, other)
    end

    # Inversion combinator: targets all regions NOT selected by this selector
    def ~ : Selector
      Selectors::Invert.new(self)
    end
  end

  module Selectors
    # Intersection combinator selector
    class And < Selector
      getter left : Selector
      getter right : Selector

      def initialize(@left : Selector, @right : Selector, weight : Float64 = 1.0)
        super(weight)
      end

      def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
        ranges_a = @left.select(buffer)
        ranges_b = @right.select(buffer)
        RangeUtils.intersect(ranges_a, ranges_b)
      end
    end

    # Union combinator selector
    class Or < Selector
      getter left : Selector
      getter right : Selector

      def initialize(@left : Selector, @right : Selector, weight : Float64 = 1.0)
        super(weight)
      end

      def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
        ranges_a = @left.select(buffer)
        ranges_b = @right.select(buffer)
        RangeUtils.union(ranges_a, ranges_b)
      end
    end

    # Inversion combinator selector
    class Invert < Selector
      getter inner : Selector

      def initialize(@inner : Selector, weight : Float64 = 1.0)
        super(weight)
      end

      def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
        ranges = @inner.select(buffer)
        RangeUtils.invert(ranges, buffer.size)
      end
    end
  end
end

require "./byte_range"
require "./header_footer"
require "./regex"
require "./delimiters"
require "./delimited_field"
require "./character_class"
require "./stride"
require "./entropy"
require "./json_path"
require "./xml_tag"
