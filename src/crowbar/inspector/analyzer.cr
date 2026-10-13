require "json"
require "digest/crc32"
require "../buffer"
require "../rules/detector"
require "../session"

module Crowbar::Inspector
  # Represents a segmented block of data with Shannon entropy metrics
  struct EntropyBlock
    include JSON::Serializable

    property index : Int32
    property offset_start : Int32
    property offset_end : Int32
    property entropy : Float64
    property classification : String

    def initialize(
      @index : Int32,
      @offset_start : Int32,
      @offset_end : Int32,
      @entropy : Float64,
      @classification : String,
    )
    end

    def visual_bar(width : Int32 = 16) : String
      # Normalized from 0.0 to 8.0
      filled = ((@entropy / 8.0) * width).round.to_i.clamp(0, width)
      empty = width - filled
      "█" * filled + "░" * empty
    end
  end

  # Represents an identified structural section or packet chunk
  struct ChunkBoundary
    include JSON::Serializable

    property offset_start : Int32
    property offset_end : Int32
    property name : String
    property description : String
    property valid : Bool?

    def initialize(
      @offset_start : Int32,
      @offset_end : Int32,
      @name : String,
      @description : String,
      @valid : Bool? = nil,
    )
    end

    def size : Int32
      [0, @offset_end - @offset_start].max
    end
  end

  # Aggregated inspection and diagnostic report
  class InspectionReport
    include JSON::Serializable

    property filename : String?
    property format : String?
    property size : Int32
    property overall_entropy : Float64
    property entropy_blocks : Array(EntropyBlock)
    property boundaries : Array(ChunkBoundary)
    property details : Hash(String, String)
    property heatmap : Array(Int32)?
    property session_id : String?

    def initialize(
      @size : Int32,
      @overall_entropy : Float64,
      @entropy_blocks : Array(EntropyBlock),
      @boundaries : Array(ChunkBoundary),
      @details : Hash(String, String) = Hash(String, String).new,
      @format : String? = nil,
      @filename : String? = nil,
      @heatmap : Array(Int32)? = nil,
      @session_id : String? = nil,
    )
    end
  end

  # Analyzes buffer structures, calculates Shannon entropy distributions,
  # and generates session mutation heatmaps.
  class Analyzer
    # Calculates Shannon entropy in bits per byte (0.0 to 8.0)
    def self.calculate_entropy(bytes : Bytes) : Float64
      return 0.0 if bytes.empty?
      counts = Hash(UInt8, Int32).new(0)
      bytes.each { |b| counts[b] += 1 }
      total = bytes.size.to_f64
      entropy = 0.0
      counts.each_value do |c|
        p = c / total
        entropy -= p * Math.log2(p)
      end
      entropy.clamp(0.0, 8.0)
    end

    # Analyzes entropy distribution across N uniform blocks
    def self.analyze_entropy_blocks(bytes : Bytes, num_blocks : Int32 = 16) : Array(EntropyBlock)
      return [] of EntropyBlock if bytes.empty?

      total_size = bytes.size
      effective_blocks = [num_blocks, total_size].min
      effective_blocks = [1, effective_blocks].max
      block_size = (total_size.to_f64 / effective_blocks).ceil.to_i

      blocks = [] of EntropyBlock
      effective_blocks.times do |idx|
        start_pos = idx * block_size
        break if start_pos >= total_size
        end_pos = [start_pos + block_size, total_size].min
        slice = bytes[start_pos...end_pos]
        ent = calculate_entropy(slice)

        classification = if ent < 1.5
                           "[Sparse/Zero]"
                         elsif ent < 3.5
                           "[Structured/Text]"
                         elsif ent < 6.0
                           "[Code/Medium]"
                         elsif ent < 7.5
                           "[Dense/Binary]"
                         else
                           "[Compressed/Random]"
                         end

        blocks << EntropyBlock.new(
          index: idx,
          offset_start: start_pos,
          offset_end: end_pos,
          entropy: (ent * 100.0).round / 100.0,
          classification: classification
        )
      end

      blocks
    end

    # Detects structural chunk boundaries for known formats
    def self.detect_boundaries(buffer : Buffer, format_sym : Symbol?) : Array(ChunkBoundary)
      boundaries = [] of ChunkBoundary
      return boundaries if buffer.empty?

      case format_sym
      when :png
        # PNG: 8-byte signature + Chunk framing (length: 4, type: 4, data: len, crc: 4)
        if buffer.size >= 8
          boundaries << ChunkBoundary.new(0, 8, "Signature", "PNG 8-byte file signature", true)
          offset = 8
          while offset + 8 <= buffer.size
            chunk_len = IO::ByteFormat::BigEndian.decode(UInt32, buffer[offset, 4].to_slice).to_i
            type_str = String.new(buffer[offset + 4, 4].to_slice) rescue "????"
            total_chunk = 4 + 4 + chunk_len + 4
            break if offset + total_chunk > buffer.size

            crc_offset = offset + 8 + chunk_len
            actual_crc = IO::ByteFormat::BigEndian.decode(UInt32, buffer[crc_offset, 4].to_slice)
            # CRC is computed over type and data
            calc_crc = Digest::CRC32.checksum(buffer[offset + 4, 4 + chunk_len].to_slice)

            is_valid = actual_crc == calc_crc
            boundaries << ChunkBoundary.new(
              offset,
              offset + total_chunk,
              "Chunk: #{type_str}",
              "#{chunk_len} B payload, CRC: 0x#{actual_crc.to_s(16).upcase}",
              is_valid
            )
            offset += total_chunk
            break if type_str == "IEND"
          end
        end
      when :bmp
        if buffer.size >= 14
          boundaries << ChunkBoundary.new(0, 14, "FileHeader", "Windows Bitmap 14-byte File Header (BM)", true)
          if buffer.size >= 54
            dib_size = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[14, 4].to_slice).to_i
            dib_end = [14 + dib_size, buffer.size].min
            boundaries << ChunkBoundary.new(14, dib_end, "DIBHeader", "DIB Bitmap Information Header (#{dib_size} B)", true)
            data_offset = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[10, 4].to_slice).to_i
            if data_offset < buffer.size
              boundaries << ChunkBoundary.new(data_offset, buffer.size, "PixelRaster", "Raw bitmap pixel array", true)
            end
          end
        end
      when :wav
        if buffer.size >= 12
          boundaries << ChunkBoundary.new(0, 12, "RIFFHeader", "RIFF WAVE container header", true)
          offset = 12
          while offset + 8 <= buffer.size
            sub_id = String.new(buffer[offset, 4].to_slice) rescue "????"
            sub_size = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[offset + 4, 4].to_slice).to_i
            total_sub = 8 + sub_size
            sub_end = [offset + total_sub, buffer.size].min
            boundaries << ChunkBoundary.new(
              offset,
              sub_end,
              "Subchunk: #{sub_id}",
              "#{sub_size} B subchunk payload",
              true
            )
            offset += total_sub
          end
        end
      when :http
        raw_str = buffer.to_s
        if crlf_idx = raw_str.index("\r\n\r\n")
          hdr_end = crlf_idx + 4
          boundaries << ChunkBoundary.new(0, hdr_end, "HTTPHeaders", "RFC 7230 request/response headers section", true)
          if hdr_end < buffer.size
            boundaries << ChunkBoundary.new(hdr_end, buffer.size, "HTTPBody", "Payload message body", true)
          end
        end
      when :jwt
        raw_str = buffer.to_s.strip
        parts = raw_str.split('.')
        if parts.size == 3
          p0_len = parts[0].bytesize
          p1_len = parts[1].bytesize
          boundaries << ChunkBoundary.new(0, p0_len, "JWTHeader", "Base64URL encoded JOSE header", true)
          boundaries << ChunkBoundary.new(p0_len + 1, p0_len + 1 + p1_len, "JWTPayload", "Base64URL encoded claims payload", true)
          boundaries << ChunkBoundary.new(p0_len + 1 + p1_len + 1, buffer.size, "JWTSignature", "JWS cryptographic signature", true)
        end
      when :wad
        if buffer.size >= 12
          wad_type = String.new(buffer[0, 4].to_slice) rescue "WAD"
          numlumps = IO::ByteFormat::LittleEndian.decode(Int32, buffer[4, 4].to_slice)
          infotbl = IO::ByteFormat::LittleEndian.decode(Int32, buffer[8, 4].to_slice)
          boundaries << ChunkBoundary.new(0, 12, "WADHeader", "#{wad_type} header (#{numlumps} lumps)", true)
          if infotbl >= 0 && infotbl + (numlumps * 16) <= buffer.size
            boundaries << ChunkBoundary.new(infotbl, infotbl + (numlumps * 16), "LumpDirectory", "#{numlumps} entry directory table", true)
          end
        end
      when :pdf
        raw_str = buffer.to_s
        if raw_str.starts_with?("%PDF-")
          hdr_end = raw_str.index("\n") || 8
          boundaries << ChunkBoundary.new(0, hdr_end, "PDFHeader", "PDF version header", true)
          if xref_idx = raw_str.rindex("startxref")
            boundaries << ChunkBoundary.new(xref_idx, buffer.size, "TrailerXRef", "PDF trailer and startxref pointer", true)
          end
        end
      when :zip
        offset = 0
        while offset + 4 <= buffer.size
          magic = buffer[offset, 4].to_slice
          if magic == Bytes[0x50, 0x4B, 0x03, 0x04]
            # Local file header
            boundaries << ChunkBoundary.new(offset, [offset + 30, buffer.size].min, "LocalFileHeader", "ZIP Local file header (PK\\x03\\x04)", true)
            offset += 30
          elsif magic == Bytes[0x50, 0x4B, 0x01, 0x02]
            # Central directory
            boundaries << ChunkBoundary.new(offset, [offset + 46, buffer.size].min, "CentralDirHeader", "ZIP Central directory header (PK\\x01\\x02)", true)
            offset += 46
          elsif magic == Bytes[0x50, 0x4B, 0x05, 0x06]
            boundaries << ChunkBoundary.new(offset, buffer.size, "EOCD", "End of Central Directory record", true)
            break
          else
            offset += 1
          end
        end
      end

      boundaries
    end

    # Analyzes a standalone buffer or file
    def self.analyze_buffer(buffer : Buffer, filename : String? = nil) : InspectionReport
      fmt = Detector.detect(buffer)
      overall_ent = (calculate_entropy(buffer.to_slice) * 100.0).round / 100.0
      blocks = analyze_entropy_blocks(buffer.to_slice, 16)
      bounds = detect_boundaries(buffer, fmt)

      details = Hash(String, String).new
      details["format"] = fmt ? fmt.to_s.upcase : "UNKNOWN"
      details["size_bytes"] = buffer.size.to_s

      if buffer.size >= 4
        magic_hex = buffer[0, [4, buffer.size].min].to_slice.map { |b| b.to_s(16).rjust(2, '0').upcase }.join(" ")
        details["magic_hex"] = magic_hex
      end

      InspectionReport.new(
        size: buffer.size,
        overall_entropy: overall_ent,
        entropy_blocks: blocks,
        boundaries: bounds,
        details: details,
        format: fmt.try(&.to_s),
        filename: filename
      )
    end

    # Analyzes a stateful session and generates a mutation heatmap
    def self.analyze_session(session : Session, session_dir : String = Session.default_dir) : InspectionReport
      baseline = session.baseline
      report = analyze_buffer(baseline, "session:#{session.id}")
      report.session_id = session.id

      # Initialize heat counter for each baseline byte offset
      heat = Array(Int32).new(baseline.size, 0)

      # Load stored item files or replay to measure mutation frequency per offset
      session.items.each do |item|
        mutant_buf : Buffer? = nil

        if fp = item.file_path
          full_path = File.join(session_dir, fp)
          if File.exists?(full_path)
            mutant_buf = Buffer.new(File.read(full_path))
          end
        end

        # Fallback to deterministic replay if item file not stored
        if mutant_buf.nil?
          mutant_buf, _ = session.replay(item.iteration)
        end

        next unless mutant_buf

        # Compare mutant bytes against baseline
        min_sz = [baseline.size, mutant_buf.size].min
        min_sz.times do |i|
          if baseline[i] != mutant_buf[i]
            heat[i] += 1
          end
        end
      end

      report.heatmap = heat
      report
    end
  end
end
