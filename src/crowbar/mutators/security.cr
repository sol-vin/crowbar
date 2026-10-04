require "./base"

module Crowbar::Mutators
  # Parser boundary validation mutator.
  # Tests parser resilience against boundary anomalies, format specifiers, path normalization,
  # null-byte termination, delimiter escapes, and numeric extremes.
  # Inspired by Radamsa's 'ab' ("bad ascii") mutator, framed for input validation QA.
  class Security < Mutator
    def name : String
      "sec"
    end

    def aliases : Array(String)
      ["ab", "bad_ascii", "security"]
    end

    def description : String
      "Inject parser boundary test vectors (format specifiers, traversal tokens, boundary escapes)"
    end

    # Curated boundary vectors for robust parser validation
    VECTORS = [
      # 1. Format string specifiers
      "%s", "%d", "%x", "%p", "%n", "%s%s%s%s%s",
      "%08x", "%#010x", "%9999999s", "%.1024d", "%2$s", "%1$n",

      # 2. Path normalization & traversal tokens
      "../", "..\\", "../../../etc/passwd", "..\\..\\..\\Windows\\System32",
      "....//", "....\\\\", "/...", "\\...", "/./", "\\.\\",

      # 3. String termination & null-byte boundary tokens
      "\0", "\0\0\0\0", "test\0.bin", "%00", "\\0", "\\x00",

      # 4. Delimiter escapes & metacharacters
      "\"", "'", "`", "\\", "/", ";", "|", "&", "&&", "||",
      "--", "/*", "*/", "-->", "<script>", "\r\n\r\n",

      # 5. Numeric boundary representations
      "-1", "0", "1", "2147483647", "-2147483648", "4294967295",
      "9223372036854775807", "-9223372036854775808", "18446744073709551615",
      "NaN", "Infinity", "-Infinity", "1e309", "-1e309",

      # 6. URL & escape sequence anomalies
      "%20", "%2e%2e%2f", "%u0000", "%c0%ae%c0%ae%c0%af",

      # 7. Buffer boundary repeated tokens
      "A" * 256,
      "A" * 1024,
      "\xff" * 64,
    ]

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b

      token_str = context.prng.choice(VECTORS)
      token_bytes = token_str.to_slice

      if len > 0 && context.prng.rand_bool(0.6)
        # Replace a segment within target range
        replace_len = [context.prng.rand(1..[token_bytes.size, len].max), len].min
        pos = b + context.prng.rand([1, len - replace_len + 1].max)
        pos = [b, [pos, e - replace_len].min].max

        buffer.replace_range(pos, replace_len, token_bytes)
        context.record_mutation(name, {pos, [pos + token_bytes.size, buffer.size].min})
      else
        # Insert boundary token at random position
        pos = b + (len > 0 ? context.prng.rand(len + 1) : 0)
        buffer.insert(pos, token_bytes)
        context.record_mutation(name, {pos, [pos + token_bytes.size, buffer.size].min})
      end

      {true, 1}
    end
  end
end
