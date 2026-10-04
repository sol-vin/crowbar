require "./spec_helper"

describe "WAD (Doom) & PDF Format Rules" do
  describe Crowbar::Rules::WADRule do
    it "matches valid IWAD and PWAD headers" do
      rule = Crowbar::Rules::WADRule.new

      # Construct minimal IWAD: 12-byte header + 1 lump directory entry (16 bytes)
      # IWAD, 1 lump, directory at offset 12
      raw = IO::Memory.new
      raw.write("IWAD".to_slice)
      IO::ByteFormat::LittleEndian.encode(1_u32, raw)
      IO::ByteFormat::LittleEndian.encode(12_u32, raw)
      # Lump entry: filepos=0, size=0, name="E1M1\0\0\0\0"
      IO::ByteFormat::LittleEndian.encode(0_u32, raw)
      IO::ByteFormat::LittleEndian.encode(0_u32, raw)
      raw.write("E1M1\0\0\0\0".to_slice)

      buf = Crowbar::Buffer.new(raw.to_slice)
      rule.match?(buf).should be_true

      # PWAD test
      raw_pwad = IO::Memory.new
      raw_pwad.write("PWAD".to_slice)
      IO::ByteFormat::LittleEndian.encode(1_u32, raw_pwad)
      IO::ByteFormat::LittleEndian.encode(12_u32, raw_pwad)
      IO::ByteFormat::LittleEndian.encode(0_u32, raw_pwad)
      IO::ByteFormat::LittleEndian.encode(0_u32, raw_pwad)
      raw_pwad.write("MAP01\0\0\0".to_slice)

      buf_pwad = Crowbar::Buffer.new(raw_pwad.to_slice)
      rule.match?(buf_pwad).should be_true

      not_wad = Crowbar::Buffer.new("NOTAWADFILE123")
      rule.match?(not_wad).should be_false
    end

    it "mutates WAD lumps and directory entries while preserving WAD framing" do
      rule = Crowbar::Rules::WADRule.new
      context = Crowbar::Context.new(42_u64)

      # Construct WAD with 1 lump (THINGS) containing 20 bytes (2 things)
      raw = IO::Memory.new
      raw.write("IWAD".to_slice)
      IO::ByteFormat::LittleEndian.encode(1_u32, raw)  # 1 lump
      IO::ByteFormat::LittleEndian.encode(32_u32, raw) # directory at offset 32

      # Lump payload at offset 12 (20 bytes: two 10-byte thing structs)
      things_data = Bytes.new(20, 0_u8)
      # Thing 1: x=100, y=200, angle=90, type=1 (Player 1), flags=7
      IO::ByteFormat::LittleEndian.encode(100_i16, things_data[0, 2])
      IO::ByteFormat::LittleEndian.encode(200_i16, things_data[2, 2])
      IO::ByteFormat::LittleEndian.encode(90_u16, things_data[4, 2])
      IO::ByteFormat::LittleEndian.encode(1_u16, things_data[6, 2])
      IO::ByteFormat::LittleEndian.encode(7_u16, things_data[8, 2])
      raw.write(things_data)

      # Directory entry at offset 32 (16 bytes)
      IO::ByteFormat::LittleEndian.encode(12_u32, raw) # filepos
      IO::ByteFormat::LittleEndian.encode(20_u32, raw) # size
      raw.write("THINGS\0\0".to_slice)

      buf = Crowbar::Buffer.new(raw.to_slice)
      rule.match?(buf).should be_true

      5.times do
        rule.apply(context, buf)
        # Header must be IWAD or PWAD
        magic = String.new(buf[0, 4].to_slice)
        (magic == "IWAD" || magic == "PWAD").should be_true
      end
    end
  end

  describe Crowbar::Rules::PDFRule do
    it "matches valid PDF header" do
      rule = Crowbar::Rules::PDFRule.new
      buf = Crowbar::Buffer.new("%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\nxref\n0 2\n0000000000 65535 f\n0000000009 00000 n\ntrailer << /Size 2 /Root 1 0 R >>\nstartxref\n59\n%%EOF\n")
      rule.match?(buf).should be_true

      not_pdf = Crowbar::Buffer.new("Hello world not a pdf")
      rule.match?(not_pdf).should be_false
    end

    it "mutates PDF while preserving %PDF- header and synchronizing startxref" do
      rule = Crowbar::Rules::PDFRule.new
      context = Crowbar::Context.new(1234_u64)

      raw = "%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R /Count 1 >> endobj\n2 0 obj << /Length 12 /Filter /FlateDecode >>\nstream\nHelloWorld12\nendstream\nendobj\nxref\n0 3\n0000000000 65535 f\n0000000009 00000 n\n0000000070 00000 n\ntrailer << /Size 3 /Root 1 0 R >>\nstartxref\n140\n%%EOF\n"
      buf = Crowbar::Buffer.new(raw)
      rule.match?(buf).should be_true

      5.times do
        rule.apply(context, buf)
        buf[0, 5].to_slice.should eq("%PDF-".to_slice)
        str = String.new(buf.to_slice)
        str.includes?("%%EOF").should be_true
        str.includes?("startxref").should be_true
      end
    end
  end

  describe "Detector with WAD and PDF" do
    it "auto-detects WAD and PDF streams" do
      # WAD detection
      wad_raw = IO::Memory.new
      wad_raw.write("IWAD".to_slice)
      IO::ByteFormat::LittleEndian.encode(0_u32, wad_raw)
      IO::ByteFormat::LittleEndian.encode(12_u32, wad_raw)
      wad_buf = Crowbar::Buffer.new(wad_raw.to_slice)
      Crowbar::Detector.detect(wad_buf).should eq(:wad)

      # PDF detection
      pdf_buf = Crowbar::Buffer.new("%PDF-1.7\n...")
      Crowbar::Detector.detect(pdf_buf).should eq(:pdf)
    end
  end
end
