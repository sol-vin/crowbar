require "./spec_helper"
require "json"
require "yaml"

describe "Crowbar Structure-Preserving Rules" do
  it "JSONRule produces syntactically valid JSON after mutation" do
    rule = Crowbar::Rules::JSONRule.new
    ctx = Crowbar::Context.new(42_u64)
    sample = %({"user": "alice", "age": 30, "admin": false, "roles": ["editor", "viewer"]})

    10.times do
      buf = Crowbar::Buffer.new(sample)
      rule.match?(buf).should be_true
      rule.apply(ctx, buf).should be_true

      # Verify mutated string is parseable JSON
      parsed = JSON.parse(buf.to_s)
      parsed.should be_a(JSON::Any)
    end
  end

  it "YAMLRule produces syntactically valid YAML after mutation" do
    rule = Crowbar::Rules::YAMLRule.new
    ctx = Crowbar::Context.new(42_u64)
    sample = "name: Bob\nscore: 100\ntags:\n  - ruby\n  - crystal\n"

    10.times do
      buf = Crowbar::Buffer.new(sample)
      rule.match?(buf).should be_true
      rule.apply(ctx, buf).should be_true

      # Verify mutated string is parseable YAML
      parsed = YAML.parse(buf.to_s)
      parsed.should be_a(YAML::Any)
    end
  end

  it "HTTPRule preserves request framing while mutating fields" do
    rule = Crowbar::Rules::HTTPRule.new
    ctx = Crowbar::Context.new(42_u64)
    sample = "GET /api/v1/users?page=1 HTTP/1.1\r\nHost: api.local\r\nAccept: application/json\r\n\r\n"

    10.times do
      buf = Crowbar::Buffer.new(sample)
      rule.match?(buf).should be_true
      rule.apply(ctx, buf).should be_true

      str = buf.to_s
      str.should contain("\r\n\r\n") # Proper CRLF header terminator
      parts = str.split("\r\n\r\n", 2)
      header_lines = parts[0].split("\r\n")
      header_lines.size.should be >= 1
    end
  end

  it "DNSRule preserves 12-byte header framing and mutates fields" do
    rule = Crowbar::Rules::DNSRule.new
    ctx = Crowbar::Context.new(42_u64)

    # Standard 12-byte DNS query header for 1 question (QDCOUNT=1) followed by "www.example.com"
    qname = Bytes[3, 'w'.ord.to_u8, 'w'.ord.to_u8, 'w'.ord.to_u8,
      7, 'e'.ord.to_u8, 'x'.ord.to_u8, 'a'.ord.to_u8, 'm'.ord.to_u8, 'p'.ord.to_u8, 'l'.ord.to_u8, 'e'.ord.to_u8,
      3, 'c'.ord.to_u8, 'o'.ord.to_u8, 'm'.ord.to_u8, 0]
    header = Bytes.new(12, 0_u8)
    IO::ByteFormat::BigEndian.encode(0x1234_u16, header[0, 2]) # ID
    IO::ByteFormat::BigEndian.encode(0x0100_u16, header[2, 2]) # Flags (RD)
    IO::ByteFormat::BigEndian.encode(1_u16, header[4, 2])      # QDCOUNT=1

    packet_bytes = IO::Memory.new
    packet_bytes.write(header)
    packet_bytes.write(qname)
    packet_bytes.write(Bytes[0x00, 0x01, 0x00, 0x01]) # QTYPE=A, QCLASS=IN

    buf = Crowbar::Buffer.new(packet_bytes.to_slice)
    rule.match?(buf).should be_true
    rule.apply(ctx, buf).should be_true
    buf.size.should be >= 12
  end
end
