require "./spec_helper"
require "../src/crowbar/rules/seven_zip"
require "../src/crowbar/rules/tar"
require "../src/crowbar/rules/zip"
require "../src/crowbar/rules/markdown"
require "../src/crowbar/rules/yaml"

describe "Advanced Storage & Document Rules" do
  context Crowbar::Rules::SevenZipRule do
    it "matches and preserves 7z archive signature and recalculates StartHeader CRC32" do
      # 32-byte 7z header:
      # Bytes 0..5: 37 7A BC AF 27 1C
      # Bytes 6..7: 00 04 (v0.4)
      # Bytes 8..11: StartHeaderCRC (UInt32 LE)
      # Bytes 12..19: NextHeaderOffset (UInt64 LE)
      # Bytes 20..27: NextHeaderSize (UInt64 LE)
      # Bytes 28..31: NextHeaderCRC (UInt32 LE)
      hdr = Bytes.new(32, 0_u8)
      Bytes[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C].copy_to(hdr[0, 6])
      hdr[6] = 0x00_u8
      hdr[7] = 0x04_u8
      # Initial StartHeader values
      IO::ByteFormat::LittleEndian.encode(100_u64, hdr[12, 8])
      IO::ByteFormat::LittleEndian.encode(50_u64, hdr[20, 8])
      IO::ByteFormat::LittleEndian.encode(0x12345678_u32, hdr[28, 4])
      # Calculate initial CRC
      init_crc = Digest::CRC32.checksum(hdr[12, 20])
      IO::ByteFormat::LittleEndian.encode(init_crc, hdr[8, 4])

      buf = Crowbar::Buffer.new(hdr)
      rule = Crowbar::Rules::SevenZipRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(42_u64)
      applied = rule.apply(ctx, buf)
      applied.should be_true

      # Verify signature is preserved
      buf[0, 6].to_slice.should eq(Bytes[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])

      # Verify StartHeader CRC32 is freshly synchronized to mutated bytes 12..31
      expected_crc = Digest::CRC32.checksum(buf[12, 20].to_slice)
      actual_crc = IO::ByteFormat::LittleEndian.decode(UInt32, buf[8, 4].to_slice)
      actual_crc.should eq(expected_crc)
    end
  end

  context Crowbar::Rules::TarRule do
    it "matches UStar tar archives and automatically recomputes octal header checksum" do
      # 512-byte tar header block
      block = Bytes.new(512, 0_u8)
      "test.txt".to_slice.copy_to(block[0, 8])
      "0000644\0".to_slice.copy_to(block[100, 8])
      "0001750\0".to_slice.copy_to(block[108, 8])
      "0001750\0".to_slice.copy_to(block[116, 8])
      "00000000020\0".to_slice.copy_to(block[124, 12]) # 16 bytes size (octal 20)
      "14000000000\0".to_slice.copy_to(block[136, 12])
      block[156] = 0x30_u8 # regular file '0'
      "ustar\0".to_slice.copy_to(block[257, 6])
      "00".to_slice.copy_to(block[263, 2])

      buf = Crowbar::Buffer.new(block)
      rule = Crowbar::Rules::TarRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(1234_u64)
      applied = rule.apply(ctx, buf)
      applied.should be_true

      buf.size.should eq(512)
      buf[257, 5].to_slice.should eq("ustar".to_slice)

      # Verify octal checksum string matches actual sum
      chksum_str = String.new(buf[148, 8].to_slice).strip
      expected_sum = rule.calculate_checksum(buf)
      octal_val = chksum_str.to_u32?(8)
      octal_val.should eq(expected_sum)
    end
  end

  context Crowbar::Rules::ZipRule do
    it "matches PKZip local file headers and preserves local framing" do
      # 30-byte local file header + filename + 10 bytes data
      filename = "data.bin"
      data = "0123456789"
      hdr = Bytes.new(30 + filename.size + data.size, 0_u8)
      Bytes[0x50, 0x4B, 0x03, 0x04].copy_to(hdr[0, 4])
      IO::ByteFormat::LittleEndian.encode(20_u16, hdr[4, 2])                # version needed
      IO::ByteFormat::LittleEndian.encode(0_u16, hdr[8, 2])                 # method 0 (store)
      IO::ByteFormat::LittleEndian.encode(filename.size.to_u16, hdr[26, 2]) # filename len
      IO::ByteFormat::LittleEndian.encode(0_u16, hdr[28, 2])                # extra len
      filename.to_slice.copy_to(hdr[30, filename.size])
      data.to_slice.copy_to(hdr[30 + filename.size, data.size])

      buf = Crowbar::Buffer.new(hdr)
      rule = Crowbar::Rules::ZipRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(99_u64)
      applied = rule.apply(ctx, buf)
      applied.should be_true

      # Verify magic bytes preserved
      buf[0, 4].to_slice.should eq(Bytes[0x50, 0x4B, 0x03, 0x04])
    end
  end

  context Crowbar::Rules::MarkdownRule do
    it "matches markdown and mutates link destinations while preserving markdown syntax" do
      md = "# Title\n\nHere is a [link](https://example.com/target) to test.\n\n```crystal\nputs 42\n```\n"
      buf = Crowbar::Buffer.new(md)
      rule = Crowbar::Rules::MarkdownRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(42_u64)
      applied = rule.apply(ctx, buf)
      applied.should be_true

      out_str = buf.to_s
      out_str.should_not eq(md)
      (out_str.includes?("[link]") || out_str.includes?("#")).should be_true
    end

    it "mutates markdown table structures and alignment rows" do
      table = "| Col A | Col B |\n| :--- | :--- |\n| Val 1 | Val 2 |\n"
      buf = Crowbar::Buffer.new(table)
      rule = Crowbar::Rules::MarkdownRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(777_u64)
      rule.apply(ctx, buf).should be_true
      buf.to_s.includes?("|").should be_true
    end
  end

  context Crowbar::Rules::YAMLRule do
    it "preserves YAML frontmatter and document body" do
      doc = "---\ntitle: Fuzzing Guide\nauthor: Antigravity\nviews: 100\n---\n# Welcome\n\nThis is markdown body content."
      buf = Crowbar::Buffer.new(doc)
      rule = Crowbar::Rules::YAMLRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(42_u64)
      rule.apply(ctx, buf).should be_true

      res = buf.to_s
      res.starts_with?("---\n").should be_true
      res.includes?("---\n# Welcome\n\nThis is markdown body content.").should be_true
    end
  end
end
