module Crowbar::Selectors
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
