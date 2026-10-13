require "json"
require "yaml"
require "csv"
require "http/request"
require "uri"
require "base64"
require "digest/crc32"
require "./target"
require "../rules/json"
require "../rules/yaml"
require "../rules/jwt"
require "../rules/http"
require "../rules/csv"
require "../rules/url"
require "../rules/base64"
require "../rules/packet"

module Crowbar::Campaign
  # Standard battery of robust targets covering core serialization,
  # network protocols, security tokens, and data formats.
  module Battery
    def self.all_targets : Array(Target)
      [
        json_target,
        yaml_target,
        jwt_target,
        http_target,
        csv_target,
        uri_target,
        base64_target,
        packet_target,
      ]
    end

    def self.json_target : Target
      target = Target.new(
        name: "json_parser",
        category: TargetCategory::Serialization,
        expected_errors: [
          JSON::ParseException,
          ArgumentError,
          TypeCastError,
          OverflowError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      target.add_sample(%({"name":"crowbar","version":"0.1.38","active":true,"tags":["fuzz","security"],"meta":{"runs":100}}))
      target.add_sample(%([{"id":1,"status":"ok"},{"id":2,"status":"pending"}]))
      target.add_rule(Rules::JSONRule.new)

      target.execution = ->(buf : Buffer) {
        JSON.parse(buf.to_s)
        nil
      }
      target
    end

    def self.yaml_target : Target
      target = Target.new(
        name: "yaml_parser",
        category: TargetCategory::Serialization,
        expected_errors: [
          YAML::ParseException,
          ArgumentError,
          TypeCastError,
          OverflowError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      target.add_sample("name: crowbar\nversion: 0.1\nfeatures:\n  - mutation\n  - fuzzing\ncount: 42\n")
      target.add_rule(Rules::YAMLRule.new)

      target.execution = ->(buf : Buffer) {
        YAML.parse(buf.to_s)
        nil
      }
      target
    end

    def self.jwt_target : Target
      target = Target.new(
        name: "jwt_validator",
        category: TargetCategory::Security,
        expected_errors: [
          ArgumentError,
          Base64::Error,
          JSON::ParseException,
          IndexError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      target.add_sample("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c")
      target.add_rule(Rules::JWTRule.new)

      target.execution = ->(buf : Buffer) {
        raw = buf.to_s.strip
        parts = raw.split('.')
        if parts.size == 3
          # Validate base64 decoding of header and payload
          hdr_bytes = Base64.decode_string(parts[0]) rescue nil
          payload_bytes = Base64.decode_string(parts[1]) rescue nil
          if hdr_bytes
            JSON.parse(hdr_bytes) rescue nil
          end
          if payload_bytes
            JSON.parse(payload_bytes) rescue nil
          end
        end
        nil
      }
      target
    end

    def self.http_target : Target
      target = Target.new(
        name: "http_request",
        category: TargetCategory::Networking,
        expected_errors: [
          ArgumentError,
          IO::Error,
          IndexError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      target.add_sample("GET /api/v1/status?verbose=true HTTP/1.1\r\nHost: sol.vin\r\nUser-Agent: Crowbar/1.0\r\nAccept: application/json\r\n\r\n")
      target.add_sample("POST /api/v1/fuzz HTTP/1.1\r\nHost: sol.vin\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"ready\":true}")
      target.add_rule(Rules::HTTPRule.new)

      target.execution = ->(buf : Buffer) {
        io = IO::Memory.new(buf.to_slice)
        HTTP::Request.from_io(io)
        nil
      }
      target
    end

    def self.csv_target : Target
      target = Target.new(
        name: "csv_parser",
        category: TargetCategory::Serialization,
        expected_errors: [
          CSV::MalformedCSVError,
          ArgumentError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      target.add_sample("id,agent,division,score\n1,Alpha,Architecture,99.9\n2,Kappa,Security,98.5\n3,Upsilon,DevOps,97.2\n")
      target.add_rule(Rules::CSVRule.new)

      target.execution = ->(buf : Buffer) {
        CSV.parse(buf.to_s)
        nil
      }
      target
    end

    def self.uri_target : Target
      target = Target.new(
        name: "uri_parser",
        category: TargetCategory::Networking,
        expected_errors: [
          URI::Error,
          ArgumentError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      target.add_sample("https://subdomain.example.com:8443/v1/resource/query?key=value&filter=active#results")
      target.add_sample("ftp://user:pass@ftp.example.com:21/files/archive.tar.gz")
      target.add_rule(Rules::URLRule.new)

      target.execution = ->(buf : Buffer) {
        URI.parse(buf.to_s)
        nil
      }
      target
    end

    def self.base64_target : Target
      target = Target.new(
        name: "base64_decoder",
        category: TargetCategory::Serialization,
        expected_errors: [
          Base64::Error,
          ArgumentError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      target.add_sample("U29sLVZpbiBBSSBDcm93YmFyIE11dGF0aW9uIEZ1enppbmcgRW5naW5lIQ==")
      target.add_rule(Rules::Base64Rule.new)

      target.execution = ->(buf : Buffer) {
        Base64.decode_string(buf.to_s)
        nil
      }
      target
    end

    def self.packet_target : Target
      target = Target.new(
        name: "packet_framing",
        category: TargetCategory::Protocol,
        expected_errors: [
          ArgumentError,
          IO::Error,
          IndexError,
        ] of Exception.class,
        timeout: 200.milliseconds
      )
      # 16-byte header: Magic (4B), Length (4B BE), CRC32 (4B BE), Reserved (4B) + 16B Body
      sample_buf = IO::Memory.new
      sample_buf.write_bytes(0xDEADBEEF_u32, IO::ByteFormat::BigEndian)
      sample_buf.write_bytes(16_u32, IO::ByteFormat::BigEndian)
      body = "1234567890abcdef".to_slice
      crc = Digest::CRC32.checksum(body)
      sample_buf.write_bytes(crc, IO::ByteFormat::BigEndian)
      sample_buf.write_bytes(0_u32, IO::ByteFormat::BigEndian)
      sample_buf.write(body)

      target.add_sample(Buffer.new(sample_buf.to_slice))
      target.add_rule(Rules::PacketRule.new)

      target.execution = ->(buf : Buffer) {
        return nil if buf.size < 16
        magic = IO::ByteFormat::BigEndian.decode(UInt32, buf[0, 4].to_slice)
        len = IO::ByteFormat::BigEndian.decode(UInt32, buf[4, 4].to_slice).to_i
        stored_crc = IO::ByteFormat::BigEndian.decode(UInt32, buf[8, 4].to_slice)
        if buf.size >= 16 + len
          actual_crc = Digest::CRC32.checksum(buf[16, len].to_slice)
        end
        nil
      }
      target
    end
  end
end
