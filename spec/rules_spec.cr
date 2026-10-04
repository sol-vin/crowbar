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

  it "HTTPRule auto-synchronizes Content-Length header with mutated body" do
    rule = Crowbar::Rules::HTTPRule.new
    rule.targets(:body)
    ctx = Crowbar::Context.new(1234_u64)
    sample = "POST /api/test HTTP/1.1\r\nHost: example.com\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\nhello world"

    10.times do
      buf = Crowbar::Buffer.new(sample)
      rule.apply(ctx, buf).should be_true

      parts = buf.to_s.split("\r\n\r\n", 2)
      headers = parts[0].split("\r\n")
      body = parts.size > 1 ? parts[1] : ""

      cl_header = headers.find { |h| h.starts_with?("Content-Length:") }
      cl_header.should_not be_nil
      cl_header.should eq("Content-Length: #{body.bytesize}")
    end
  end

  it "HTTPRule delegates to nested body_rule for JSON payloads" do
    rule = Crowbar::Rules::HTTPRule.new
    rule.targets(:body)
    rule.body_rule(:json)
    ctx = Crowbar::Context.new(42_u64)
    sample = "POST /data HTTP/1.1\r\nHost: api.local\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"num\": 12345}"

    5.times do
      buf = Crowbar::Buffer.new(sample)
      rule.apply(ctx, buf).should be_true

      parts = buf.to_s.split("\r\n\r\n", 2)
      body = parts[1]
      # Body must remain valid JSON
      parsed = JSON.parse(body)
      parsed.should be_a(JSON::Any)
    end
  end

  it "FTPRule maintains RFC 959 CRLF line structure while mutating commands" do
    rule = Crowbar::Rules::FTPRule.new
    ctx = Crowbar::Context.new(777_u64)
    sample = "USER testuser\r\nPASS secret\r\nPORT 192,168,0,1,10,20\r\nRETR file.txt\r\nQUIT\r\n"

    10.times do
      buf = Crowbar::Buffer.new(sample)
      rule.match?(buf).should be_true
      rule.apply(ctx, buf).should be_true

      str = buf.to_s
      str.ends_with?("\r\n").should be_true
      lines = str.split("\r\n").reject(&.empty?)
      lines.each do |line|
        verb = line.split(" ", 2)[0]
        Crowbar::Rules::FTPRule::COMMON_COMMANDS.includes?(verb).should be_true
      end
    end
  end

  it "SQLRule preserves query structure while mutating numeric and string literals" do
    rule = Crowbar::Rules::SQLRule.new
    ctx = Crowbar::Context.new(888_u64)
    sample = "SELECT id, name FROM users WHERE age > 21 AND status = 'active';"

    10.times do
      buf = Crowbar::Buffer.new(sample)
      rule.match?(buf).should be_true
      rule.apply(ctx, buf).should be_true

      str = buf.to_s
      str.should contain("SELECT")
      str.should contain("FROM")
      str.should contain("WHERE")
    end
  end
end
