require "./base"

module Crowbar::Mutators
  # Replaces textual integers or floats with boundary values (underflow, overflow, off-by-one)
  class BoundaryNumbers < Mutator
    BOUNDARIES = [
      "0", "1", "-1", "2", "-2",
      "127", "128", "-128", "-129",
      "255", "256", "-256",
      "32767", "32768", "-32768", "-32769",
      "65535", "65536",
      "2147483647", "2147483648", "-2147483648", "-2147483649",
      "4294967295", "4294967296",
      "9007199254740991", "9007199254740992", # 2^53 - 1 JS safe integer
      "9223372036854775807", "9223372036854775808", "-9223372036854775808",
      "18446744073709551615",
      "NaN", "+Infinity", "-Infinity", "0.0", "-0.0", "1e308", "1e-308",
    ]

    def name : String
      "num"
    end

    def description : String
      "Mutate textual numbers to boundary values or off-by-one"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      # Search for sequences of digits
      digit_spans = [] of Tuple(Int32, Int32)
      in_digits = false
      start_digit = 0

      (b...e).each do |i|
        byte = buffer[i]
        is_digit = byte >= 0x30_u8 && byte <= 0x39_u8 # '0'..'9'
        if is_digit && !in_digits
          in_digits = true
          start_digit = i
        elsif !is_digit && in_digits
          in_digits = false
          digit_spans << {start_digit, i}
        end
      end
      digit_spans << {start_digit, e} if in_digits

      return {false, -1} if digit_spans.empty?

      span_start, span_end = context.prng.choice(digit_spans)
      span_len = span_end - span_start

      # Strategy: 50% boundary replacement, 50% arithmetic off-by-one
      replacement = if context.prng.rand_bool
                      context.prng.choice(BOUNDARIES).to_slice
                    else
                      raw_str = String.new(buffer[span_start...span_end])
                      if num = raw_str.to_i64?
                        case context.prng.rand(4)
                        when 0 then (num &+ 1).to_s.to_slice
                        when 1 then (num &- 1).to_s.to_slice
                        when 2 then (num &* 2).to_s.to_slice
                        else        (-num).to_s.to_slice
                        end
                      else
                        context.prng.choice(BOUNDARIES).to_slice
                      end
                    end

      buffer.replace_range(span_start, span_len, replacement)
      context.record_mutation(name, {span_start, span_start + replacement.size})
      {true, 2} # Strong positive feedback for finding textual numbers
    end
  end

  # Injects Unicode edge cases, overlong representations, surrogates, and BiDi controls
  class UnicodeEdgeCases < Mutator
    UNICODE_SNIPPETS = [
      # Byte Order Marks (BOM)
      Bytes[0xEF, 0xBB, 0xBF], # UTF-8 BOM
      Bytes[0xFE, 0xFF],       # UTF-16 BE BOM
      Bytes[0xFF, 0xFE],       # UTF-16 LE BOM
      # Directional Overrides & Controls
      Bytes[0xE2, 0x80, 0xAE], # U+202E Right-to-Left Override
      Bytes[0xE2, 0x80, 0xAD], # U+202D Left-to-Right Override
      Bytes[0xE2, 0x80, 0x8B], # U+200B Zero-Width Space
      Bytes[0xE2, 0x80, 0x8C], # U+200C Zero-Width Non-Joiner
      Bytes[0xE2, 0x80, 0x8D], # U+200D Zero-Width Joiner
      # Non-characters & Max values
      Bytes[0xEF, 0xBF, 0xBF],       # U+FFFF Non-character
      Bytes[0xF4, 0x8F, 0xBF, 0xBF], # U+10FFFF Max Unicode Code Point
      Bytes[0xF4, 0x90, 0x80, 0x80], # Beyond U+10FFFF (Invalid code point)
      # Surrogates (Invalid in UTF-8)
      Bytes[0xED, 0xA0, 0x80], # U+D800 High surrogate start
      Bytes[0xED, 0xBF, 0xBF], # U+DFFF Low surrogate end
      # Multi-byte expansion (U+FDFD expands by 11x under NFKC)
      Bytes[0xEF, 0xB7, 0xBA], # U+FDFD
    ]

    def name : String
      "ui"
    end

    def description : String
      "Inject Unicode boundaries, BOMs, surrogates, and BiDi controls"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      pos = b + (len > 0 ? context.prng.rand(len + 1) : 0)

      snippet = context.prng.choice(UNICODE_SNIPPETS)
      buffer.insert(pos, snippet)

      context.record_mutation(name, {pos, pos + snippet.size})
      {true, 1}
    end
  end

  # Modifies whitespace and delimiters
  class WhitespaceDelimiters < Mutator
    WHITESPACES = [
      Bytes[0x0D, 0x0A],       # CRLF
      Bytes[0x0A],             # LF
      Bytes[0x0D],             # CR
      Bytes[0x00],             # NUL
      Bytes[0x09],             # TAB
      Bytes[0x20, 0x20, 0x20], # Multiple spaces
    ]

    def name : String
      "wd"
    end

    def description : String
      "Vary whitespace formatting, line breaks (CRLF/LF), and null characters"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len)
      ws = context.prng.choice(WHITESPACES)
      buffer.insert(pos, ws)

      context.record_mutation(name, {pos, pos + ws.size})
      {true, 0}
    end
  end
end
