require "../buffer"

module Crowbar
  # Automatic format and protocol detector inspecting magic bytes, framing signatures,
  # and syntactical prefixes across media, network protocols, structured data, and code.
  module Detector
    # Inspects buffer contents and returns the best-matching format symbol, or nil if undetermined.
    def self.detect(buffer : Buffer) : Symbol?
      return nil if buffer.empty?

      # 1. Binary Formats & Media Signatures
      # PNG: 89 50 4E 47 0D 0A 1A 0A
      if buffer.size >= 8 && buffer[0, 8].to_slice == Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return :png
      end

      # BMP: "BM" magic + DIB header size >= 40
      if buffer.size >= 54 && buffer[0] == 0x42_u8 && buffer[1] == 0x4D_u8
        dib_size = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[14, 4].to_slice) rescue 0_u32
        return :bmp if dib_size >= 40_u32
      end

      # WAV / RIFF: "RIFF" .... "WAVE"
      if buffer.size >= 12 && buffer[0, 4].to_slice == "RIFF".to_slice && buffer[8, 4].to_slice == "WAVE".to_slice
        return :wav
      end

      # MP3: ID3v2 tag or MPEG audio frame sync
      if buffer.size >= 10 && buffer[0, 3].to_slice == "ID3".to_slice
        return :mp3
      end
      if buffer.size >= 4 && buffer[0] == 0xFF_u8 && (buffer[1] & 0xE0_u8) == 0xE0_u8
        return :mp3
      end

      # Doom WAD: "IWAD" or "PWAD"
      if buffer.size >= 12
        magic = buffer[0, 4].to_slice
        if magic == Bytes[0x49, 0x57, 0x41, 0x44] || magic == Bytes[0x50, 0x57, 0x41, 0x44]
          return :wad
        end
      end

      # PDF: "%PDF-"
      if buffer.size >= 8 && buffer[0, 5].to_slice == "%PDF-".to_slice
        return :pdf
      end

      # 7-Zip: 37 7A BC AF 27 1C
      if buffer.size >= 32 && buffer[0, 6].to_slice == Bytes[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
        return :seven_zip
      end

      # ZIP: "PK\x03\x04"
      if buffer.size >= 30 && buffer[0, 4].to_slice == Bytes[0x50, 0x4B, 0x03, 0x04]
        return :zip
      end

      # TAR: "ustar" at offset 257
      if buffer.size >= 512 && buffer[257, 5].to_slice == "ustar".to_slice
        return :tar
      end

      # PCAP capture trace
      if buffer.size >= 24
        magic = buffer[0, 4].to_slice
        if magic == Bytes[0xD4, 0xC3, 0xB2, 0xA1] || magic == Bytes[0xA1, 0xB2, 0xC3, 0xD4]
          return :packet
        end
      end

      # Raw IPv4 packet: Version 4, IHL >= 5, known protocol (TCP 6, UDP 17, ICMP 1)
      if buffer.size >= 20 && ((buffer[0] >> 4) & 0x0F) == 4 && (buffer[0] & 0x0F) >= 5
        proto = buffer[9]
        if proto == 6_u8 || proto == 17_u8 || proto == 1_u8
          return :packet
        end
      end

      # DNS wire packet: QDCOUNT >= 1 and <= 10 at offset 4
      if buffer.size >= 12
        qdcount = IO::ByteFormat::BigEndian.decode(UInt16, buffer[4, 2].to_slice) rescue 0_u16
        # Distinguish binary DNS from plain text by checking if byte 0 or 1 is non-ASCII
        if qdcount >= 1_u16 && qdcount <= 10_u16 && (buffer[0] < 0x20_u8 || buffer[1] < 0x20_u8 || buffer[4] == 0_u8)
          return :dns
        end
      end

      # 2. Text-Based Protocols & Structured Formats
      str = String.new(buffer.to_slice) rescue nil
      if str
        trimmed = str.lstrip
        up = trimmed.upcase

        # HTTP Request / Response
        if trimmed.starts_with?("GET ") || trimmed.starts_with?("POST ") ||
           trimmed.starts_with?("PUT ") || trimmed.starts_with?("DELETE ") ||
           trimmed.starts_with?("PATCH ") || trimmed.starts_with?("HEAD ") ||
           trimmed.starts_with?("OPTIONS ") || trimmed.starts_with?("HTTP/1.") ||
           trimmed.starts_with?("HTTP/2")
          return :http
        end

        # FTP Command / Response
        if up.starts_with?("USER ") || up.starts_with?("PASS ") ||
           up.starts_with?("PORT ") || up.starts_with?("RETR ") ||
           up.starts_with?("STOR ") || up.starts_with?("QUIT ") ||
           trimmed.starts_with?("220 ") || trimmed.starts_with?("331 ") ||
           trimmed.starts_with?("230 ")
          return :ftp
        end

        # SQL Statement
        if up.starts_with?("SELECT ") || up.starts_with?("INSERT INTO ") ||
           up.starts_with?("UPDATE ") || up.starts_with?("DELETE FROM ") ||
           up.starts_with?("CREATE TABLE ") || up.starts_with?("DROP TABLE ") ||
           up.starts_with?("ALTER TABLE ") || up.starts_with?("WITH ")
          return :sql
        end

        # XML / HTML
        if trimmed.starts_with?("<?xml") || (trimmed.starts_with?("<") && trimmed.includes?(">") && !trimmed.starts_with?("<<"))
          return :xml
        end

        # JSON
        if (trimmed.starts_with?("{") && trimmed.ends_with?("}")) ||
           (trimmed.starts_with?("[") && trimmed.ends_with?("]"))
          return :json
        end

        # Markdown (CommonMark): headings, links, code blocks, or tables
        if trimmed.starts_with?("# ") || trimmed.starts_with?("## ") || trimmed.includes?("](") || trimmed.includes?("```") || trimmed.includes?("| ---")
          return :markdown
        end

        # YAML
        if trimmed.starts_with?("---") || (trimmed.includes?(":\n") || trimmed.includes?(": ")) && trimmed.includes?("\n")
          return :yaml
        end

        # URL
        if trimmed.starts_with?("http://") || trimmed.starts_with?("https://") ||
           trimmed.starts_with?("ftp://") || trimmed.starts_with?("ws://") ||
           trimmed.starts_with?("wss://")
          return :url
        end

        # CSV / TSV
        if trimmed.includes?("\n") && (trimmed.count(',') >= 3 || trimmed.count('\t') >= 3)
          return :csv
        end
      end

      nil
    end
  end
end
