require "../src/crowbar"

# Crowbar HTTP Request Fuzzer:
# Demonstrates structure-preserving HTTP/1.x message mutation.
# Preserves strict RFC 7230 CRLF framing while fuzzing paths, headers, and payloads.

fuzzer = Crowbar.define do
  seed 12345_u64
  preserve :http
end

sample_request = "POST /api/v1/auth/login?redirect=/dashboard HTTP/1.1\r\n" \
                 "Host: api.example.com\r\n" \
                 "User-Agent: Crowbar/1.0\r\n" \
                 "Content-Type: application/json\r\n" \
                 "Content-Length: 35\r\n" \
                 "\r\n" \
                 "{\"user\": \"admin\", \"token\": \"secret\"}"

puts "=== Original HTTP Request ==="
puts sample_request
puts "============================="
puts ""

puts "=== Generating 4 Mutated HTTP Requests ==="
4.times do |i|
  mutant = fuzzer.fuzz(sample_request)
  puts "--- [Mutant ##{i + 1}] ---"
  puts mutant
  puts "-------------------------"
end
