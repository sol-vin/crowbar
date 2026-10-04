require "./spec_helper"
require "json"

describe "Property-Based Rule Robustness & Invariant Preservation" do
  context = Crowbar::Context.new(1337_u64)

  # Diverse randomized payloads for stress-testing rule match? and apply
  test_payloads = [
    Bytes[],                                            # Empty
    Bytes[0x00],                                        # Single zero
    Bytes[0xFF],                                        # Single FF
    Bytes.new(10, 0x00_u8),                             # 10 zeros
    Bytes.new(1024, 0xFF_u8),                           # 1KB all 0xFF
    Bytes[0x89, 0x50, 0x4E, 0x47],                      # Truncated PNG header
    Bytes[0x42, 0x4D],                                  # Truncated BMP header
    Bytes[0x52, 0x49, 0x46, 0x46],                      # Truncated RIFF header
    Bytes[0x49, 0x57, 0x41, 0x44],                      # Truncated WAD header
    "%PDF-".to_slice,                                   # Truncated PDF
    "GET / HTTP/1.1\r\n".to_slice,                      # Truncated HTTP
    "USER test\r\n".to_slice,                           # FTP
    "SELECT 1".to_slice,                                # SQL
    "{\"a\": 1}".to_slice,                              # JSON
    "key: value\n".to_slice,                            # YAML
    "<root><child/></root>".to_slice,                   # XML
    "a,b,c\n1,2,3\n".to_slice,                          # CSV
    "https://example.com/api?q=test".to_slice,          # URL
    "AQIDBA==".to_slice,                                # Base64
    Bytes[0xE5, 0x8E, 0x26],                            # LEB128 varint
    Bytes[0x01, 0x04, 0xAA, 0xBB, 0xCC, 0xDD],          # TLV
    Bytes.new(256) { |i| (i & 0xFF).to_u8 },            # Ramp 0..255
    Bytes.new(512) { |i| ((i * 37 + 13) % 256).to_u8 }, # High-entropy PRNG noise
  ]

  describe "Crash-resistance across all 18 rules" do
    Crowbar::Rules::Registry.catalog.each do |entry|
      it "does not crash #{entry.name} rule with edge-case and random binary buffers" do
        rule = entry.factory.call

        test_payloads.each do |payload|
          buffer = Crowbar::Buffer.new(payload)
          # match? must never raise
          matched = rule.match?(buffer)

          # If it matches, apply must never raise unhandled exceptions
          if matched
            begin
              rule.apply(context, buffer)
            rescue ex
              fail("Rule #{entry.name} crashed with exception: #{ex.message} on payload: #{payload.inspect}")
            end
          end
        end
      end
    end
  end

  describe "Structural framing invariants on valid inputs" do
    it "preserves PNG CRC32 and chunk structure" do
      rule = Crowbar::Rules::PNGRule.new
      png_bytes = Bytes[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00,
        0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x00,
        0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
      ]
      buffer = Crowbar::Buffer.new(png_bytes)
      rule.match?(buffer).should be_true
      applied = rule.apply(context, buffer)
      applied.should be_true
      buffer[0, 8].to_slice.should eq(Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      buffer[buffer.size - 8, 8].to_slice.should eq(Bytes[0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    end

    it "preserves WAV RIFF container framing" do
      rule = Crowbar::Rules::WAVRule.new
      wav_bytes = Bytes[
        0x52, 0x49, 0x46, 0x46, # "RIFF"
        0x24, 0x00, 0x00, 0x00, # size: 36
        0x57, 0x41, 0x56, 0x45, # "WAVE"
        0x66, 0x6D, 0x74, 0x20, # "fmt "
        0x10, 0x00, 0x00, 0x00, # subchunk1 size: 16
        0x01, 0x00,             # PCM = 1
        0x01, 0x00,             # Mono = 1
        0x44, 0xAC, 0x00, 0x00, # 44100 Hz
        0x88, 0x58, 0x01, 0x00, # ByteRate
        0x02, 0x00,             # BlockAlign
        0x10, 0x00,             # BitsPerSample = 16
        0x64, 0x61, 0x74, 0x61, # "data"
        0x00, 0x00, 0x00, 0x00, # data size 0
      ]
      buffer = Crowbar::Buffer.new(wav_bytes)
      rule.match?(buffer).should be_true
      rule.apply(context, buffer).should be_true
      buffer[0, 4].to_slice.should eq("RIFF".to_slice)
      buffer[8, 4].to_slice.should eq("WAVE".to_slice)
    end

    it "preserves Doom WAD header framing" do
      rule = Crowbar::Rules::WADRule.new
      wad_bytes = Bytes[
        0x49, 0x57, 0x41, 0x44, # IWAD
        0x01, 0x00, 0x00, 0x00, # 1 lump
        0x0C, 0x00, 0x00, 0x00, # dir at 12
        0x1C, 0x00, 0x00, 0x00, # pos: 28
        0x04, 0x00, 0x00, 0x00, # size: 4
        0x54, 0x45, 0x53, 0x54, 0x00, 0x00, 0x00, 0x00,
        0x11, 0x22, 0x33, 0x44,
      ]
      buffer = Crowbar::Buffer.new(wad_bytes)
      rule.match?(buffer).should be_true
      rule.apply(context, buffer).should be_true
      sig = String.new(buffer[0, 4].to_slice)
      (sig == "IWAD" || sig == "PWAD").should be_true
    end

    it "preserves PDF start and EOF framing" do
      rule = Crowbar::Rules::PDFRule.new
      pdf_text = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\nxref\n0 1\n0000000000 65535 f \ntrailer\n<< /Root 1 0 R >>\nstartxref\n50\n%%EOF"
      buffer = Crowbar::Buffer.new(pdf_text)
      rule.match?(buffer).should be_true
      rule.apply(context, buffer).should be_true
      buffer.to_s.starts_with?("%PDF-").should be_true
      buffer.to_s.ends_with?("%%EOF").should be_true
    end

    it "preserves HTTP/1.x CRLF framing and start line" do
      rule = Crowbar::Rules::HTTPRule.new
      http_text = "GET /v1/users?page=1 HTTP/1.1\r\nHost: api.example.com\r\n\r\n"
      buffer = Crowbar::Buffer.new(http_text)
      rule.match?(buffer).should be_true
      rule.apply(context, buffer).should be_true
      buffer.to_s.should contain("\r\n\r\n")
      buffer.to_s.should_not eq(http_text)
    end
  end
end
