require "base64"
require "./buffer"

module Crowbar
  # Binary Input and Output Representation Codecs.
  # Provides transparent conversion between human-friendly CLI string encodings
  # (hexadecimal, C-escapes, bitstrings, base64) and raw binary buffers.
  module Encoding
    # Supported input and output encoding format identifiers
    enum Format
      Raw
      Hex
      Escape
      Bit
      Base64
      Auto

      def self.parse?(str : String) : Format?
        case str.downcase.strip
        when "raw", "bytes", "bin-raw"
          Raw
        when "hex", "x", "0x", "hexdump"
          Hex
        when "escape", "c", "escaped", "slash"
          Escape
        when "bit", "bits", "bin", "binary", "0b"
          Bit
        when "base64", "b64"
          Base64
        when "auto", "detect"
          Auto
        else
          nil
        end
      end
    end

    # Auto-detects the most probable encoding of an input string representation
    def self.detect(input : String) : Format
      trimmed = input.strip
      return Format::Raw if trimmed.empty?

      if trimmed.starts_with?("0x") || trimmed.starts_with?("0X")
        return Format::Hex
      end

      if trimmed.starts_with?("0b") || trimmed.starts_with?("0B")
        return Format::Bit
      end

      if trimmed.includes?("\\x") || trimmed.includes?("\\0")
        return Format::Escape
      end

      # Check if entire string is formatted hex (e.g. "64afde" or "64:af:de" or "64 af de")
      cleaned = trimmed.gsub(/[\s:,]/, "")
      if cleaned.size >= 2 && cleaned.size % 2 == 0 && cleaned.matches?(/^[0-9a-fA-F]+$/)
        # Avoid misclassifying pure decimal text like "123456" as hex unless length > 8 or has a-f
        if cleaned.matches?(/[a-fA-F]/) || trimmed.includes?(" ") || trimmed.includes?(":") || trimmed.includes?(",")
          return Format::Hex
        end
      end

      Format::Raw
    end

    # Decodes an input string, bytes, or buffer into a raw binary Buffer
    def self.decode(input : String | Bytes | Buffer, format : Format | String | Symbol = Format::Raw) : Buffer
      fmt = case format
            when Format then format
            when Symbol then Format.parse?(format.to_s) || Format::Raw
            when String then Format.parse?(format) || Format::Raw
            else             Format::Raw
            end

      str_input = case input
                  when Buffer then input.to_s
                  when Bytes  then String.new(input)
                  else             input.to_s
                  end

      case fmt
      when Format::Auto
        detected = detect(str_input)
        decode(str_input, detected)
      when Format::Hex
        decode_hex(str_input)
      when Format::Escape
        decode_escape(str_input)
      when Format::Bit
        decode_bit(str_input)
      when Format::Base64
        decode_base64(str_input)
      when Format::Raw
        case input
        when Buffer then input.dup
        when Bytes  then Buffer.new(input)
        else             Buffer.new(str_input.to_slice)
        end
      else
        Buffer.new
      end
    end

    # Decodes hexadecimal string representations (e.g. "414243", "0x41 0x42", "41:42:43")
    def self.decode_hex(str : String) : Buffer
      cleaned = str.strip
      if cleaned.starts_with?("0x") || cleaned.starts_with?("0X")
        cleaned = cleaned[2..]
      end
      # Strip spaces, commas, colons, and prefix instances like "0x"
      cleaned = cleaned.gsub(/0[xX]/, "").gsub(/[\s:,]/, "")
      return Buffer.new if cleaned.empty?

      # Pad odd length with leading zero
      cleaned = "0" + cleaned if cleaned.size.odd?

      bytes = Bytes.new(cleaned.size // 2)
      i = 0
      while i < cleaned.size
        chunk = cleaned[i, 2]
        val = chunk.to_u8?(16) || 0_u8
        bytes[i // 2] = val
        i += 2
      end
      Buffer.new(bytes)
    end

    # Decodes C-style escape representations (e.g. "\x64\xaf\x00\r\n\t")
    def self.decode_escape(str : String) : Buffer
      io = IO::Memory.new
      i = 0
      bytes = str.to_slice

      while i < bytes.size
        b = bytes[i]
        if b == 0x5C_u8 # Backslash '\'
          if i + 1 < bytes.size
            next_b = bytes[i + 1]
            case next_b.chr
            when 'x', 'X'
              # Hex escape: \xHH
              if i + 3 < bytes.size
                hex_str = String.new(bytes[i + 2, 2])
                if val = hex_str.to_u8?(16)
                  io.write_byte(val)
                  i += 4
                  next
                end
              elsif i + 2 < bytes.size
                hex_str = String.new(bytes[i + 2, 1])
                if val = hex_str.to_u8?(16)
                  io.write_byte(val)
                  i += 3
                  next
                end
              end
              io.write_byte(0x5C_u8)
              i += 1
            when '0'
              io.write_byte(0x00_u8)
              i += 2
            when 'n'
              io.write_byte(0x0A_u8)
              i += 2
            when 'r'
              io.write_byte(0x0D_u8)
              i += 2
            when 't'
              io.write_byte(0x09_u8)
              i += 2
            when '\\'
              io.write_byte(0x5C_u8)
              i += 2
            when '\''
              io.write_byte(0x27_u8)
              i += 2
            when '"'
              io.write_byte(0x22_u8)
              i += 2
            when 'a'
              io.write_byte(0x07_u8)
              i += 2
            when 'b'
              io.write_byte(0x08_u8)
              i += 2
            when 'f'
              io.write_byte(0x0C_u8)
              i += 2
            when 'v'
              io.write_byte(0x0B_u8)
              i += 2
            else
              # Unrecognized escape, write escaped char
              io.write_byte(next_b)
              i += 2
            end
          else
            io.write_byte(0x5C_u8)
            i += 1
          end
        else
          io.write_byte(b)
          i += 1
        end
      end

      Buffer.new(io.to_slice)
    end

    # Decodes bitstring representations (e.g. "0b01010100 01110010" or "0101010001110010")
    def self.decode_bit(str : String) : Buffer
      cleaned = str.strip
      if cleaned.starts_with?("0b") || cleaned.starts_with?("0B")
        cleaned = cleaned[2..]
      end
      cleaned = cleaned.gsub(/[\s_]/, "")
      return Buffer.new if cleaned.empty?

      # Pad with leading zeros to 8-bit byte boundary
      remainder = cleaned.size % 8
      if remainder != 0
        cleaned = ("0" * (8 - remainder)) + cleaned
      end

      num_bytes = cleaned.size // 8
      bytes = Bytes.new(num_bytes)

      num_bytes.times do |byte_idx|
        chunk = cleaned[byte_idx * 8, 8]
        val = chunk.to_u8?(2) || 0_u8
        bytes[byte_idx] = val
      end

      Buffer.new(bytes)
    end

    # Decodes Base64 strings to raw binary Buffer
    def self.decode_base64(str : String) : Buffer
      cleaned = str.strip.gsub(/\s+/, "")
      return Buffer.new if cleaned.empty?
      decoded = Base64.decode(cleaned)
      Buffer.new(decoded)
    rescue
      Buffer.new
    end

    # Encodes a binary buffer into the requested string representation
    def self.encode(buffer : Buffer | Bytes, format : Format | String | Symbol = Format::Raw) : String
      fmt = case format
            when Format then format
            when Symbol then Format.parse?(format.to_s) || Format::Raw
            when String then Format.parse?(format) || Format::Raw
            else             Format::Raw
            end

      slice = case buffer
              when Buffer then buffer.to_slice
              else             buffer
              end

      case fmt
      when Format::Hex
        slice.hexstring.downcase
      when Format::Escape
        io = IO::Memory.new
        slice.each do |b|
          case b
          when 0x00_u8
            io << "\\0"
          when 0x0A_u8
            io << "\\n"
          when 0x0D_u8
            io << "\\r"
          when 0x09_u8
            io << "\\t"
          when 0x5C_u8
            io << "\\\\"
          when 0x22_u8
            io << "\\\""
          when 0x20_u8..0x7E_u8
            io << b.chr
          else
            io << sprintf("\\x%02x", b)
          end
        end
        io.to_s
      when Format::Bit
        io = IO::Memory.new
        slice.each do |b|
          io << sprintf("%08b", b)
        end
        io.to_s
      when Format::Base64
        Base64.strict_encode(slice)
      when Format::Raw, Format::Auto
        String.new(slice) rescue slice.hexstring.downcase
      else
        ""
      end
    end
  end
end
