require "./base"

module Crowbar::Mutators
  # Stresses parser recursion limits and call-stack depth by expanding or injecting deeply nested delimiters
  class NestingDepth < Mutator
    PAIRS = [
      {"[", "]"},
      {"{", "}"},
      {"(", ")"},
      {"<", ">"},
      {"\"[", "]\""},
    ]

    def name : String
      "nest"
    end

    def description : String
      "Deeply nest balanced delimiters to test parser recursion depth and stack safety"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      pos = b + (len > 0 ? context.prng.rand(len + 1) : 0)

      # Depth between 32 and 128 levels
      depth = context.prng.rand(32..128)
      open_tok, close_tok = context.prng.choice(PAIRS)

      io = IO::Memory.new
      depth.times { io << open_tok }
      io << "0" # Inner leaf
      depth.times { io << close_tok }

      snippet = io.to_slice
      buffer.insert(pos, snippet)
      context.record_mutation(name, {pos, pos + snippet.size})
      {true, 2}
    end
  end

  # Explores boundary conditions in textual and protocol length representations
  class LengthBoundary < Mutator
    BOUNDARIES = [
      "0", "1", "-1",
      "255", "256",
      "32767", "32768", "-32768",
      "65535", "65536",
      "2147483647", "2147483648", "-2147483648",
      "4294967295", "4294967296",
      "18446744073709551615",
    ]

    def name : String
      "len"
    end

    def description : String
      "Mutate length fields to boundary, off-by-one, or zero values to test allocation limits"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      # Search for numeric sequences (textual length candidates)
      digit_spans = [] of Tuple(Int32, Int32)
      in_digits = false
      start_digit = 0

      (b...e).each do |i|
        byte = buffer[i]
        is_digit = byte >= 0x30_u8 && byte <= 0x39_u8
        if is_digit && !in_digits
          in_digits = true
          start_digit = i
        elsif !is_digit && in_digits
          in_digits = false
          digit_spans << {start_digit, i}
        end
      end
      digit_spans << {start_digit, e} if in_digits

      if digit_spans.empty?
        # If no digits found, insert a boundary length at a random position
        pos = b + context.prng.rand(len + 1)
        val = context.prng.choice(BOUNDARIES).to_slice
        buffer.insert(pos, val)
        context.record_mutation(name, {pos, pos + val.size})
        return {true, 1}
      end

      span_start, span_end = context.prng.choice(digit_spans)
      span_len = span_end - span_start

      # 50% boundary value, 50% relative to actual buffer size
      replacement = if context.prng.rand_bool
                      context.prng.choice(BOUNDARIES).to_slice
                    else
                      rel = case context.prng.rand(4)
                            when 0 then 0
                            when 1 then buffer.size
                            when 2 then buffer.size &+ 1
                            else        [0, buffer.size &- 1].max
                            end
                      rel.to_s.to_slice
                    end

      buffer.replace_range(span_start, span_len, replacement)
      context.record_mutation(name, {span_start, span_start + replacement.size})
      {true, 2}
    end
  end

  # Injects IEEE-754 floating-point edge cases and extreme exponents
  class FloatAnomalies < Mutator
    FLOAT_BOUNDARIES = [
      "NaN", "-NaN",
      "+Infinity", "-Infinity", "Infinity",
      "0.0", "-0.0",
      "1e308", "-1e308", "1e-308",
      "1e-324",                  # Subnormal float64 boundary
      "2.2250738585072014e-308", # Smallest normal float64
      "1.7976931348623157e+308", # Max float64
      "1e999999999",             # Parser exponent overflow
    ]

    def name : String
      "flt"
    end

    def description : String
      "Inject IEEE-754 float edge cases (NaN, Infinity, -0.0, subnormals, extreme exponents)"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      matches = [] of Tuple(Int32, Int32)
      in_num = false
      start_num = 0

      (b...e).each do |i|
        byte = buffer[i]
        is_num_char = (byte >= 0x30_u8 && byte <= 0x39_u8) ||
                      byte == 0x2E_u8 || byte == 0x2D_u8 || byte == 0x2B_u8 ||
                      byte == 0x65_u8 || byte == 0x45_u8
        if is_num_char && !in_num
          in_num = true
          start_num = i
        elsif !is_num_char && in_num
          in_num = false
          matches << {start_num, i}
        end
      end
      matches << {start_num, e} if in_num

      snippet = context.prng.choice(FLOAT_BOUNDARIES).to_slice

      if matches.empty?
        pos = b + context.prng.rand(len + 1)
        buffer.insert(pos, snippet)
        context.record_mutation(name, {pos, pos + snippet.size})
        {true, 1}
      else
        span_s, span_e = context.prng.choice(matches)
        buffer.replace_range(span_s, span_e - span_s, snippet)
        context.record_mutation(name, {span_s, span_s + snippet.size})
        {true, 2}
      end
    end
  end

  # Stresses delimiter parsing with mixed line breaks, header continuations, and repeated separators
  class DelimiterStress < Mutator
    DELIM_SNIPPETS = [
      Bytes[0x0D],                         # Bare CR (\r)
      Bytes[0x0A, 0x0D],                   # Reverse CRLF (\n\r)
      Bytes[0x0D, 0x0A, 0x20],             # Header folding: CRLF + Space
      Bytes[0x0D, 0x0A, 0x09],             # Header folding: CRLF + Tab
      Bytes[0x00, 0x0D, 0x0A],             # NUL before CRLF
      Bytes[0x2C, 0x2C, 0x2C, 0x2C, 0x2C], # Repeated commas ",,,,,"
      Bytes[0x3A, 0x3A, 0x3A],             # Repeated colons ":::"
      Bytes[0x09, 0x09, 0x09, 0x09],       # Repeated tabs "\t\t\t\t"
      Bytes[0x3B, 0x3B, 0x3B],             # Repeated semicolons ";;;"
    ]

    def name : String
      "delim"
    end

    def description : String
      "Inject unusual line separators, header folding whitespace, and repeated delimiters"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      pos = b + context.prng.rand(len + 1)
      snippet = context.prng.choice(DELIM_SNIPPETS)
      buffer.insert(pos, snippet)

      context.record_mutation(name, {pos, pos + snippet.size})
      {true, 1}
    end
  end
end
