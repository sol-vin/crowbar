module Crowbar::Selectors
  # Selects contiguous byte sequences matching specified character classes:
  # :digits, :hex, :alpha, :alphanumeric, :printable, :whitespace, :high_bytes.
  class CharacterClass < Selector
    enum Kind
      Digits
      Hex
      Alpha
      Alphanumeric
      Printable
      Whitespace
      HighBytes
    end

    getter kind : Kind
    getter min_length : Int32

    def initialize(kind : Kind | Symbol, @min_length : Int32 = 1, weight : Float64 = 1.0)
      super(weight)
      @kind = case kind
              when Kind                           then kind
              when :digits, :digit                then Kind::Digits
              when :hex                           then Kind::Hex
              when :alpha                         then Kind::Alpha
              when :alnum, :alphanumeric          then Kind::Alphanumeric
              when :printable, :ascii             then Kind::Printable
              when :whitespace, :space            then Kind::Whitespace
              when :high, :high_bytes, :non_ascii then Kind::HighBytes
              else
                raise "Unknown character class: #{kind}"
              end
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) if buffer.empty?

      matches = [] of Tuple(Int32, Int32)
      in_run = false
      run_start = 0

      (0...buffer.size).each do |i|
        b = buffer[i]
        matched = byte_matches?(b)

        if matched && !in_run
          in_run = true
          run_start = i
        elsif !matched && in_run
          in_run = false
          if i - run_start >= @min_length
            matches << {run_start, i}
          end
        end
      end

      if in_run && buffer.size - run_start >= @min_length
        matches << {run_start, buffer.size}
      end

      matches
    end

    private def byte_matches?(b : UInt8) : Bool
      case @kind
      when Kind::Digits
        b >= 0x30_u8 && b <= 0x39_u8
      when Kind::Hex
        (b >= 0x30_u8 && b <= 0x39_u8) || (b >= 0x41_u8 && b <= 0x46_u8) || (b >= 0x61_u8 && b <= 0x66_u8)
      when Kind::Alpha
        (b >= 0x41_u8 && b <= 0x5A_u8) || (b >= 0x61_u8 && b <= 0x7A_u8)
      when Kind::Alphanumeric
        (b >= 0x30_u8 && b <= 0x39_u8) || (b >= 0x41_u8 && b <= 0x5A_u8) || (b >= 0x61_u8 && b <= 0x7A_u8)
      when Kind::Printable
        b >= 0x20_u8 && b <= 0x7E_u8
      when Kind::Whitespace
        b == 0x20_u8 || b == 0x09_u8 || b == 0x0A_u8 || b == 0x0D_u8
      when Kind::HighBytes
        b >= 0x80_u8
      else
        false
      end
    end
  end
end
