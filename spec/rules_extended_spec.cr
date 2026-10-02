require "./spec_helper"
require "csv"
require "xml"
require "uri"
require "base64"

describe "Extended Structure-Preserving Rules" do
  describe Crowbar::Rules::CSVRule do
    it "matches and mutates CSV data while preserving valid tabular syntax" do
      rule = Crowbar::Rules::CSVRule.new
      input = "name,age,city\nalice,30,paris\nbob,25,london\n"
      buffer = Crowbar::Buffer.new(input)
      context = Crowbar::Context.new(1234_u64)

      rule.match?(buffer).should be_true
      applied = rule.apply(context, buffer)
      applied.should be_true

      # Mutated output must be valid parseable CSV
      mutated_csv = buffer.to_s
      parsed = CSV.parse(mutated_csv)
      parsed.size.should be >= 1
    end
  end

  describe Crowbar::Rules::XMLRule do
    it "matches and mutates XML markup while maintaining valid well-formed XML" do
      rule = Crowbar::Rules::XMLRule.new
      input = "<library><book id=\"1\"><title>War and Peace</title></book></library>"
      buffer = Crowbar::Buffer.new(input)
      context = Crowbar::Context.new(5678_u64)

      rule.match?(buffer).should be_true
      applied = rule.apply(context, buffer)
      applied.should be_true

      # Mutated output must be valid XML
      mutated_xml = buffer.to_s
      doc = XML.parse(mutated_xml)
      doc.root.should_not be_nil
    end
  end

  describe Crowbar::Rules::URLRule do
    it "matches and mutates URLs and query strings while maintaining valid URI syntax" do
      rule = Crowbar::Rules::URLRule.new
      input = "https://example.com/api/v1/search?q=crystal&page=1"
      buffer = Crowbar::Buffer.new(input)
      context = Crowbar::Context.new(9999_u64)

      rule.match?(buffer).should be_true
      applied = rule.apply(context, buffer)
      applied.should be_true

      # Mutated output must be valid URI
      mutated_url = buffer.to_s
      uri = URI.parse(mutated_url)
      uri.scheme.should_not be_nil
    end
  end

  describe Crowbar::Rules::TLVRule do
    it "matches and mutates binary TLV frames" do
      rule = Crowbar::Rules::TLVRule.new

      # Build 2 TLV frames: [Tag: 0x0001, Len: 4, "TEST"], [Tag: 0x0002, Len: 4, "DATA"]
      io = IO::Memory.new
      io.write_bytes(1_u16, IO::ByteFormat::BigEndian)
      io.write_bytes(4_u16, IO::ByteFormat::BigEndian)
      io.write("TEST".to_slice)
      io.write_bytes(2_u16, IO::ByteFormat::BigEndian)
      io.write_bytes(4_u16, IO::ByteFormat::BigEndian)
      io.write("DATA".to_slice)

      buffer = Crowbar::Buffer.new(io.to_slice)
      context = Crowbar::Context.new(4321_u64)

      rule.match?(buffer).should be_true
      applied = rule.apply(context, buffer)
      applied.should be_true
      buffer.size.should be >= 4
    end
  end

  describe Crowbar::Rules::Base64Rule do
    it "matches, mutates decoded payload, and re-encodes valid Base64" do
      rule = Crowbar::Rules::Base64Rule.new
      raw_payload = "Sensitive Payload Inside Base64"
      encoded = Base64.strict_encode(raw_payload)

      buffer = Crowbar::Buffer.new(encoded)
      context = Crowbar::Context.new(1122_u64)

      rule.match?(buffer).should be_true
      applied = rule.apply(context, buffer)
      applied.should be_true

      # Mutated output must be valid decodable Base64
      mutated_str = buffer.to_s.strip
      decoded = Base64.decode(mutated_str)
      decoded.size.should be > 0
    end
  end

  describe Crowbar::Rules::VarintRule do
    it "matches and mutates LEB128 varints" do
      rule = Crowbar::Rules::VarintRule.new
      # Encode 300 in varint: 0xAC 0x02
      varint_bytes = Bytes[0xAC_u8, 0x02_u8]
      buffer = Crowbar::Buffer.new(varint_bytes)
      context = Crowbar::Context.new(7788_u64)

      rule.match?(buffer).should be_true
      applied = rule.apply(context, buffer)
      applied.should be_true
      buffer.size.should be >= 1
    end
  end
end
