module Crowbar::Selectors
  # Selects the N-th field or column delimited by a separator (e.g. CSV column, passwd line).
  # Supports per-record (line-by-line) evaluation or global streaming evaluation.
  class DelimitedField < Selector
    getter field_index : Int32
    getter delimiter : UInt8
    getter? line_delimited : Bool
    getter? handle_quotes : Bool

    def initialize(
      @field_index : Int32,
      delimiter : UInt8 | Char | String = ',',
      @line_delimited : Bool = true,
      @handle_quotes : Bool = true,
      weight : Float64 = 1.0,
    )
      super(weight)
      @delimiter = case delimiter
                   when UInt8 then delimiter
                   when Char  then delimiter.ord.to_u8
                   else            delimiter.empty? ? 0x2C_u8 : delimiter.to_slice[0]
                   end
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      return [] of Tuple(Int32, Int32) if buffer.empty?

      if @line_delimited
        ranges = [] of Tuple(Int32, Int32)
        # Find lines
        line_start = 0
        (0...buffer.size).each do |i|
          if buffer[i] == 0x0A_u8 # '\n'
            line_end = (i > line_start && buffer[i - 1] == 0x0D_u8) ? i - 1 : i
            if line_end > line_start
              select_in_range(buffer, line_start, line_end, ranges)
            end
            line_start = i + 1
          end
        end
        if line_start < buffer.size
          select_in_range(buffer, line_start, buffer.size, ranges)
        end
        ranges
      else
        ranges = [] of Tuple(Int32, Int32)
        select_in_range(buffer, 0, buffer.size, ranges)
        ranges
      end
    end

    private def select_in_range(
      buffer : Buffer,
      start_offset : Int32,
      end_offset : Int32,
      output : Array(Tuple(Int32, Int32)),
    )
      fields = [] of Tuple(Int32, Int32)
      f_start = start_offset
      in_quotes = false
      pos = start_offset

      while pos < end_offset
        b = buffer[pos]
        if @handle_quotes && b == 0x22_u8 # '"'
          in_quotes = !in_quotes
        elsif !in_quotes && b == @delimiter
          fields << {f_start, pos}
          f_start = pos + 1
        end
        pos += 1
      end
      fields << {f_start, end_offset}

      return if fields.empty?

      idx = if @field_index < 0
              fields.size + @field_index
            else
              @field_index
            end

      if idx >= 0 && idx < fields.size
        s, e = fields[idx]
        output << {s, e} if s < e
      end
    end
  end
end
