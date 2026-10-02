require "./base"

module Crowbar::Mutators
  # Discovers textual numeric integers or floats and applies arithmetic scaling factors or shifts
  class ArithmeticScaler < Mutator
    def name : String
      "scale"
    end

    def description : String
      "Scale textual numbers by factors (2x, 10x, 100x, 0.5x, bit-shifts)"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      # Locate numeric spans
      spans = find_numeric_spans(buffer, b, e)
      return {false, -1} if spans.empty?

      span_start, span_end = context.prng.choice(spans)
      span_str = String.new(buffer[span_start...span_end])

      replacement = if span_str.includes?('.')
                      scale_float(span_str, context)
                    else
                      scale_int(span_str, context)
                    end

      return {false, 0} unless replacement

      replacement_bytes = replacement.to_slice
      buffer.replace_range(span_start, span_end - span_start, replacement_bytes)
      context.record_mutation(name, {span_start, span_start + replacement_bytes.size})
      {true, 2}
    end

    private def find_numeric_spans(buffer : Buffer, b : Int32, e : Int32) : Array(Tuple(Int32, Int32))
      spans = [] of Tuple(Int32, Int32)
      in_num = false
      start_idx = 0

      (b...e).each do |i|
        byte = buffer[i]
        is_num_char = (byte >= 0x30_u8 && byte <= 0x39_u8) || byte == 0x2D_u8 || byte == 0x2E_u8 # '0'-'9', '-', '.'
        if is_num_char && !in_num
          in_num = true
          start_idx = i
        elsif !is_num_char && in_num
          in_num = false
          spans << {start_idx, i} if i > start_idx
        end
      end
      spans << {start_idx, e} if in_num && e > start_idx
      spans
    end

    private def scale_int(str : String, context : Context) : String?
      val = str.to_i64?
      return nil unless val

      scaled = case context.prng.rand(7)
               when 0 then val &* 2_i64
               when 1 then val &* 10_i64
               when 2 then val &* 100_i64
               when 3 then val // 2_i64
               when 4 then val // 10_i64
               when 5 then val &+ 1_i64
               else        -val
               end
      scaled.to_s
    end

    private def scale_float(str : String, context : Context) : String?
      val = str.to_f64?
      return nil unless val

      scaled = case context.prng.rand(5)
               when 0 then val * 2.0
               when 1 then val * 10.0
               when 2 then val / 2.0
               when 3 then val / 10.0
               else        -val
               end
      scaled.to_s
    end
  end

  # Injects critical temporal boundary dates and timestamps (Y2038, epoch 0, leap seconds)
  class TimestampMutator < Mutator
    EPOCH_BOUNDARIES = [
      "0",                   # 1970-01-01T00:00:00Z
      "-1",                  # 1969-12-31T23:59:59Z
      "2147483647",          # 2038-01-19T03:14:07Z (Y2038 32-bit wrap)
      "2147483648",          # 2038-01-19T03:14:08Z (32-bit overflow)
      "4294967295",          # 2106-02-07T06:28:15Z (32-bit unsigned wrap)
      "9223372036854775807", # Max Int64
      "-62135596800",        # Year 0001-01-01
      "253402300799",        # Year 9999-12-31
    ]

    ISO_BOUNDARIES = [
      "1970-01-01T00:00:00Z",
      "2038-01-19T03:14:07Z",
      "2024-02-29T23:59:59Z", # Leap day
      "2000-02-29T00:00:00Z", # Century leap day
      "1900-02-29T00:00:00Z", # Invalid non-leap century day
      "2016-12-31T23:59:60Z", # Leap second
      "9999-12-31T23:59:59Z",
      "0000-00-00T00:00:00Z", # Zero date
    ]

    def name : String
      "time"
    end

    def description : String
      "Inject temporal epoch boundaries (Y2038, zero epoch, leap days)"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      # 1. Search for ISO date pattern: 4 digits, '-', 2 digits, '-', 2 digits
      if iso_range = find_iso_date(buffer, b, e)
        s, end_idx = iso_range
        sub = context.prng.choice(ISO_BOUNDARIES).to_slice
        buffer.replace_range(s, end_idx - s, sub)
        context.record_mutation(name, {s, s + sub.size})
        return {true, 2}
      end

      # 2. Search for 9 to 13 consecutive digits
      if digit_range = find_consecutive_digits(buffer, b, e, 9, 13)
        s, end_idx = digit_range
        sub = context.prng.choice(EPOCH_BOUNDARIES).to_slice
        buffer.replace_range(s, end_idx - s, sub)
        context.record_mutation(name, {s, s + sub.size})
        return {true, 2}
      end

      # Fallback: insert epoch at random pos
      pos = b + context.prng.rand(len)
      sub = context.prng.choice(EPOCH_BOUNDARIES).to_slice
      buffer.insert(pos, sub)
      context.record_mutation(name, {pos, pos + sub.size})
      {true, 0}
    end

    private def find_iso_date(buffer : Buffer, b : Int32, e : Int32) : Tuple(Int32, Int32)?
      return nil if (e - b) < 10
      (b..(e - 10)).each do |i|
        if is_digit?(buffer[i]) && is_digit?(buffer[i + 1]) && is_digit?(buffer[i + 2]) && is_digit?(buffer[i + 3]) &&
           buffer[i + 4] == 0x2D_u8 &&
           is_digit?(buffer[i + 5]) && is_digit?(buffer[i + 6]) &&
           buffer[i + 7] == 0x2D_u8 &&
           is_digit?(buffer[i + 8]) && is_digit?(buffer[i + 9])
          end_pos = i + 10
          while end_pos < e && buffer[end_pos] != 0x22_u8 && buffer[end_pos] != 0x27_u8 && buffer[end_pos] != 0x20_u8 && buffer[end_pos] != 0x0A_u8
            end_pos += 1
          end
          return {i, end_pos}
        end
      end
      nil
    end

    private def find_consecutive_digits(buffer : Buffer, b : Int32, e : Int32, min_d : Int32, max_d : Int32) : Tuple(Int32, Int32)?
      in_run = false
      run_start = 0

      (b...e).each do |i|
        if is_digit?(buffer[i])
          if !in_run
            in_run = true
            run_start = i
          end
        else
          if in_run
            in_run = false
            count = i - run_start
            return {run_start, i} if count >= min_d && count <= max_d
          end
        end
      end

      if in_run
        count = e - run_start
        return {run_start, e} if count >= min_d && count <= max_d
      end

      nil
    end

    private def is_digit?(b : UInt8) : Bool
      b >= 0x30_u8 && b <= 0x39_u8
    end
  end
end
