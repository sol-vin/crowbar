require "./spec_helper"
require "digest/crc32"

describe "Media Format Rules & Detector" do
  describe Crowbar::Rules::PNGRule do
    it "matches valid PNG signature" do
      rule = Crowbar::Rules::PNGRule.new
      png_header = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]
      buf = Crowbar::Buffer.new(png_header)
      rule.match?(buf).should be_true

      not_png = Crowbar::Buffer.new("GIF89a...")
      rule.match?(not_png).should be_false
    end

    it "preserves PNG signature and recalculates valid CRC32 on chunk mutation" do
      rule = Crowbar::Rules::PNGRule.new
      context = Crowbar::Context.new(42_u64)

      # Construct minimal PNG with IHDR and IEND
      ihdr_data = Bytes[
        0x00, 0x00, 0x00, 0x01, # Width: 1
        0x00, 0x00, 0x00, 0x01, # Height: 1
        0x08,                   # Bit depth: 8
        0x02,                   # Color type: 2 (RGB)
        0x00,                   # Compression: 0
        0x00,                   # Filter: 0
        0x00                    # Interlace: 0
      ]
      ihdr_type_data = Bytes.new(4 + ihdr_data.size)
      ihdr_type_data[0, 4].copy_from("IHDR".to_slice)
      ihdr_type_data[4, ihdr_data.size].copy_from(ihdr_data)
      ihdr_crc = Digest::CRC32.checksum(ihdr_type_data)

      raw = IO::Memory.new
      # PNG signature
      raw.write(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      # IHDR chunk
      IO::ByteFormat::BigEndian.encode(13_u32, raw)
      raw.write("IHDR".to_slice)
      raw.write(ihdr_data)
      IO::ByteFormat::BigEndian.encode(ihdr_crc, raw)
      # IEND chunk
      IO::ByteFormat::BigEndian.encode(0_u32, raw)
      raw.write("IEND".to_slice)
      iend_crc = Digest::CRC32.checksum("IEND".to_slice)
      IO::ByteFormat::BigEndian.encode(iend_crc, raw)

      buf = Crowbar::Buffer.new(raw.to_slice)
      rule.match?(buf).should be_true

      # Apply multiple mutations
      5.times do
        rule.apply(context, buf)
        # Signature must remain untouched
        buf[0, 8].to_slice.should eq(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        # Verify parsed chunks have valid CRC32
        chunks = rule.parse_chunks(buf)
        chunks.empty?.should be_false
        chunks.each do |c|
          c_data = buf[c.offset + 4, 4 + c.length].to_slice
          expected_crc = Digest::CRC32.checksum(c_data)
          actual_crc = IO::ByteFormat::BigEndian.decode(UInt32, buf[c.crc_offset, 4].to_slice)
          actual_crc.should eq(expected_crc)
        end
      end
    end
  end

  describe Crowbar::Rules::BMPRule do
    it "matches valid BMP header" do
      rule = Crowbar::Rules::BMPRule.new
      raw = Bytes.new(54, 0_u8)
      raw[0] = 0x42_u8                                        # 'B'
      raw[1] = 0x4D_u8                                        # 'M'
      IO::ByteFormat::LittleEndian.encode(40_u32, raw[14, 4]) # DIB header size
      buf = Crowbar::Buffer.new(raw)

      rule.match?(buf).should be_true
    end

    it "mutates BMP while preserving BM signature and synchronizing file size" do
      rule = Crowbar::Rules::BMPRule.new
      context = Crowbar::Context.new(12345_u64)

      raw = Bytes.new(54 + 16, 0xAA_u8)
      raw[0] = 0x42_u8
      raw[1] = 0x4D_u8
      IO::ByteFormat::LittleEndian.encode((54 + 16).to_u32, raw[2, 4])
      IO::ByteFormat::LittleEndian.encode(54_u32, raw[10, 4]) # data offset
      IO::ByteFormat::LittleEndian.encode(40_u32, raw[14, 4]) # DIB size
      IO::ByteFormat::LittleEndian.encode(4_i32, raw[18, 4])  # width
      IO::ByteFormat::LittleEndian.encode(4_i32, raw[22, 4])  # height
      IO::ByteFormat::LittleEndian.encode(1_u16, raw[26, 2])  # planes
      IO::ByteFormat::LittleEndian.encode(24_u16, raw[28, 2]) # bpp

      buf = Crowbar::Buffer.new(raw)

      5.times do
        rule.apply(context, buf)
        buf[0].should eq(0x42_u8)
        buf[1].should eq(0x4D_u8)
        # File size at offset 2 should match buffer size
        file_size = IO::ByteFormat::LittleEndian.decode(UInt32, buf[2, 4].to_slice)
        file_size.should eq(buf.size.to_u32)
      end
    end
  end

  describe Crowbar::Rules::WAVRule do
    it "matches valid RIFF/WAVE stream" do
      rule = Crowbar::Rules::WAVRule.new
      raw = IO::Memory.new
      raw.write("RIFF".to_slice)
      IO::ByteFormat::LittleEndian.encode(36_u32, raw)
      raw.write("WAVE".to_slice)
      raw.write("fmt ".to_slice)
      IO::ByteFormat::LittleEndian.encode(16_u32, raw)
      IO::ByteFormat::LittleEndian.encode(1_u16, raw)      # PCM
      IO::ByteFormat::LittleEndian.encode(2_u16, raw)      # Stereo
      IO::ByteFormat::LittleEndian.encode(44100_u32, raw)  # 44.1 kHz
      IO::ByteFormat::LittleEndian.encode(176400_u32, raw) # Byte rate
      IO::ByteFormat::LittleEndian.encode(4_u16, raw)      # Block align
      IO::ByteFormat::LittleEndian.encode(16_u16, raw)     # 16-bit
      raw.write("data".to_slice)
      IO::ByteFormat::LittleEndian.encode(4_u32, raw)
      raw.write(Bytes[0x00, 0x11, 0x22, 0x33])

      buf = Crowbar::Buffer.new(raw.to_slice)
      rule.match?(buf).should be_true

      context = Crowbar::Context.new(999_u64)
      5.times do
        rule.apply(context, buf)
        buf[0, 4].to_slice.should eq("RIFF".to_slice)
        buf[8, 4].to_slice.should eq("WAVE".to_slice)
      end
    end
  end

  describe Crowbar::Rules::MP3Rule do
    it "matches ID3 tags and MPEG frame syncs" do
      rule = Crowbar::Rules::MP3Rule.new

      # ID3 prefix
      id3_buf = Crowbar::Buffer.new("ID3\x03\x00\x00\x00\x00\x00\x10ExtraID3DataHere...")
      rule.match?(id3_buf).should be_true

      # MPEG Frame sync (0xFF 0xFB)
      mpeg_buf = Crowbar::Buffer.new(Bytes[0xFF, 0xFB, 0x90, 0x64, 0x00, 0x11, 0x22, 0x33])
      rule.match?(mpeg_buf).should be_true
    end

    it "mutates MPEG frame header while preserving sync word" do
      rule = Crowbar::Rules::MP3Rule.new
      context = Crowbar::Context.new(777_u64)

      # 1 frame header + 32 bytes payload
      raw = Bytes.new(36, 0x55_u8)
      raw[0] = 0xFF_u8
      raw[1] = 0xFB_u8 # Layer III, no CRC
      raw[2] = 0x90_u8 # 128 kbps, 44.1 kHz
      raw[3] = 0x64_u8 # Joint stereo

      buf = Crowbar::Buffer.new(raw)
      rule.match?(buf).should be_true

      5.times do
        rule.apply(context, buf)
        # MPEG sync (11 bits = 0xFF followed by high 3 bits set)
        buf[0].should eq(0xFF_u8)
        (buf[1] & 0xE0_u8).should eq(0xE0_u8)
      end
    end
  end

  describe Crowbar::Detector do
    it "accurately detects all formats by magic bytes and framing" do
      # PNG
      png = Crowbar::Buffer.new(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
      Crowbar::Detector.detect(png).should eq(:png)

      # BMP
      bmp_raw = Bytes.new(54, 0_u8)
      bmp_raw[0] = 0x42_u8
      bmp_raw[1] = 0x4D_u8
      IO::ByteFormat::LittleEndian.encode(40_u32, bmp_raw[14, 4])
      bmp = Crowbar::Buffer.new(bmp_raw)
      Crowbar::Detector.detect(bmp).should eq(:bmp)

      # WAV
      wav_raw = IO::Memory.new
      wav_raw.write("RIFF".to_slice)
      IO::ByteFormat::LittleEndian.encode(20_u32, wav_raw)
      wav_raw.write("WAVE".to_slice)
      wav = Crowbar::Buffer.new(wav_raw.to_slice)
      Crowbar::Detector.detect(wav).should eq(:wav)

      # MP3 ID3
      mp3_id3 = Crowbar::Buffer.new("ID3\x03\x00\x00\x00\x00\x00\x00AudioPayload")
      Crowbar::Detector.detect(mp3_id3).should eq(:mp3)

      # MP3 raw frame
      mp3_frame = Crowbar::Buffer.new(Bytes[0xFF, 0xFB, 0x90, 0x64])
      Crowbar::Detector.detect(mp3_frame).should eq(:mp3)

      # HTTP
      http = Crowbar::Buffer.new("GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n")
      Crowbar::Detector.detect(http).should eq(:http)

      # FTP
      ftp = Crowbar::Buffer.new("USER anonymous\r\n")
      Crowbar::Detector.detect(ftp).should eq(:ftp)

      # SQL
      sql = Crowbar::Buffer.new("SELECT id, name FROM users WHERE id = 1;")
      Crowbar::Detector.detect(sql).should eq(:sql)

      # JSON
      json = Crowbar::Buffer.new("{\"user\": \"alice\", \"id\": 10}")
      Crowbar::Detector.detect(json).should eq(:json)

      # XML
      xml = Crowbar::Buffer.new("<?xml version=\"1.0\"?><root><item>test</item></root>")
      Crowbar::Detector.detect(xml).should eq(:xml)
    end
  end
end
