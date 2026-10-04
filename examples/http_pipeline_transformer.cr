require "../src/crowbar"
require "json"

# Crowbar HTTP Request Pipeline Transformer:
# Demonstrates structure-preserving HTTP/1.x message transformation (RFC 7230).
#
# NOTE: This does NOT open or connect to any network sockets!
# It is a pure in-memory and Unix pipe (STDIN -> STDOUT) data transformer.
#
# Features demonstrated:
# 1. Strict RFC 7230 CRLF (\r\n) framing.
# 2. Automatic synchronization of Content-Length to match mutated body size.
# 3. Nested rule delegation: fuzzing a JSON body while preserving valid JSON AST.
# 4. Selective target mutation (headers, query params, body).

fuzzer = Crowbar.define do
  seed 42_u64

  http do
    sync_content_length = true
    body_rule :json # Delegate body mutation to JSONRule so inner payload remains valid JSON
  end
end

sample_http_request = "POST /api/v2/checkout?discount=SUMMER2026 HTTP/1.1\r\n" \
                      "Host: shop.example.com\r\n" \
                      "User-Agent: Crowbar-Pipes/1.0\r\n" \
                      "Content-Type: application/json\r\n" \
                      "Content-Length: 46\r\n" \
                      "\r\n" \
                      "{\"item_id\": 9912, \"qty\": 2, \"coupon\": \"VALID\"}"

puts "============================================================"
puts "  CROWBAR HTTP PIPELINE TRANSFORMER (RFC 7230)"
puts "  (Pure text transformation - No network sockets used!)"
puts "============================================================"
puts ""
puts "--- [Original HTTP Request In] ---"
puts sample_http_request
puts "----------------------------------"
puts ""

puts "=== Generating 4 Protocol-Adherent Mutated Requests ==="
4.times do |i|
  mutant = fuzzer.fuzz(sample_http_request).to_s

  # Verify protocol adherence:
  parts = mutant.split("\r\n\r\n", 2)
  headers = parts[0].split("\r\n")
  body = parts.size > 1 ? parts[1] : ""
  cl_header = headers.find { |h| h =~ /^content-length\s*:/i }

  puts "--- [Mutated Request ##{i + 1}] ---"
  puts mutant
  puts "----------------------------------"
  puts "  -> Valid CRLF Framing: #{mutant.includes?("\r\n\r\n")}"
  if cl_header
    puts "  -> Stored #{cl_header} | Actual Body Bytes: #{body.bytesize} (Synced: #{cl_header.ends_with?(body.bytesize.to_s)})"
  end
  if parts[0].includes?("application/json") && !body.empty?
    is_valid_json = begin
      JSON.parse(body)
      true
    rescue
      false
    end
    puts "  -> Nested JSON Body Valid: #{is_valid_json}"
  end
  puts ""
end
