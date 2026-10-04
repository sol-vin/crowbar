require "./base"

module Crowbar::Mutators
  # Flips letter casing: uppercase to lowercase, lowercase to uppercase, alternating, or all-caps
  class CaseFlip < Mutator
    def name : String
      "cf"
    end

    def description : String
      "Invert or alternate case (test case-folding and normalization)"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      # Find alphabetical bytes in range
      alpha_indices = [] of Int32
      (b...e).each do |i|
        byte = buffer[i]
        is_alpha = (byte >= 0x41_u8 && byte <= 0x5A_u8) || (byte >= 0x61_u8 && byte <= 0x7A_u8)
        alpha_indices << i if is_alpha
      end

      return {false, -1} if alpha_indices.empty?

      strategy = context.prng.rand(3)
      case strategy
      when 0 # Flip single random character
        idx = context.prng.choice(alpha_indices)
        buffer[idx] ^= 0x20_u8 # XOR with 0x20 flips upper/lower in ASCII
      when 1                   # Alternating casing across all alpha characters in range
        alpha_indices.each_with_index do |idx, step|
          byte = buffer[idx]
          if step.even?
            # uppercase
            buffer[idx] = byte & ~0x20_u8 if byte >= 0x61_u8
          else
            # lowercase
            buffer[idx] = byte | 0x20_u8 if byte <= 0x5A_u8
          end
        end
      else # Invert all alpha characters in range
        alpha_indices.each do |idx|
          buffer[idx] ^= 0x20_u8
        end
      end

      context.record_mutation(name, {alpha_indices.first, alpha_indices.last + 1})
      {true, 1}
    end
  end

  # Replaces ASCII letters with visually identical or confusable Unicode homoglyphs (Cyrillic, Greek, Fullwidth)
  class HomoglyphMutator < Mutator
    HOMOGLYPHS = {
      0x61_u8 => "а", # 'a' -> Cyrillic 'а' U+0430
      0x63_u8 => "с", # 'c' -> Cyrillic 'с' U+0441
      0x65_u8 => "е", # 'e' -> Cyrillic 'е' U+0435
      0x69_u8 => "і", # 'i' -> Cyrillic 'і' U+0456
      0x6A_u8 => "ј", # 'j' -> Cyrillic 'ј' U+0458
      0x6F_u8 => "о", # 'o' -> Cyrillic 'о' U+043E
      0x70_u8 => "р", # 'p' -> Cyrillic 'р' U+0440
      0x73_u8 => "ѕ", # 's' -> Cyrillic 'ѕ' U+0455
      0x78_u8 => "х", # 'x' -> Cyrillic 'х' U+0445
      0x79_u8 => "у", # 'y' -> Cyrillic 'у' U+0443
      0x41_u8 => "А", # 'A' -> Cyrillic 'А' U+0410
      0x42_u8 => "В", # 'B' -> Cyrillic 'В' U+0412
      0x45_u8 => "Е", # 'E' -> Cyrillic 'Е' U+0415
      0x48_u8 => "Н", # 'H' -> Cyrillic 'Н' U+041D
      0x4F_u8 => "О", # 'O' -> Cyrillic 'О' U+041E
      0x50_u8 => "Р", # 'P' -> Cyrillic 'Р' U+0420
      0x54_u8 => "Т", # 'T' -> Cyrillic 'Т' U+0422
      0x58_u8 => "Х", # 'X' -> Cyrillic 'Х' U+0425
    }

    def name : String
      "homo"
    end

    def description : String
      "Substitute ASCII letters with confusable Unicode homoglyphs"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if len <= 0

      # Find candidate characters with homoglyphs
      candidates = [] of Int32
      (b...e).each do |i|
        candidates << i if HOMOGLYPHS.has_key?(buffer[i])
      end

      return {false, -1} if candidates.empty?

      idx = context.prng.choice(candidates)
      glyph = HOMOGLYPHS[buffer[idx]]
      glyph_bytes = glyph.to_slice

      buffer.replace_range(idx, 1, glyph_bytes)
      context.record_mutation(name, {idx, idx + glyph_bytes.size})
      {true, 1}
    end
  end

  # Injects or replaces tokens from a configurable or built-in token vocabulary
  class DictionaryMutator < Mutator
    DEFAULT_TOKENS = [
      "null", "nil", "true", "false", "undefined", "NaN", "Infinity",
      "0", "1", "-1", "undefined", "None",
      "GET", "POST", "PUT", "DELETE", "OPTIONS",
      "application/json", "text/html", "multipart/form-data",
      "localhost", "127.0.0.1", "::1", "0.0.0.0",
      "admin", "root", "guest", "anonymous",
      "Bearer", "Basic", "token", "password",
      "<?xml", "<!DOCTYPE", "<html", "<script",
    ]

    property tokens : Array(String)

    def initialize(custom_tokens : Array(String)? = nil, weight : Float64 = 1.0)
      super(weight)
      @tokens = custom_tokens ? custom_tokens.dup : DEFAULT_TOKENS.dup
    end

    def add_tokens(new_tokens : Iterable(String))
      new_tokens.each do |tok|
        @tokens << tok unless @tokens.includes?(tok)
      end
    end

    def name : String
      "dict"
    end

    def description : String
      "Insert or replace tokens using vocabulary dictionary"
    end

    def mutate(context : Context, buffer : Buffer, target_range : Tuple(Int32, Int32)? = nil) : Tuple(Bool, Int32)
      b, e = resolve_range(buffer, target_range)
      len = e - b
      return {false, -1} if @tokens.empty?

      token = context.prng.choice(@tokens).to_slice

      if len > 0 && context.prng.rand_bool
        # Replace word/token if delimiter found
        pos = b + context.prng.rand(len)
        replace_len = [context.prng.rand(1..16), e - pos].min
        buffer.replace_range(pos, replace_len, token)
        context.record_mutation(name, {pos, pos + token.size})
      else
        pos = b + (len > 0 ? context.prng.rand(len + 1) : 0)
        buffer.insert(pos, token)
        context.record_mutation(name, {pos, pos + token.size})
      end

      {true, 1}
    end
  end
end
