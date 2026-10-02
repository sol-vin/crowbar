require "../src/crowbar"

# Modernized Crowbar DSL demo:
# Fuzzes a structured packet (16-byte header + JSON payload)
# Ensures JSON remains valid and recalculates payload length in the header!

fuzzer = Crowbar.define do
  seed 42_u64

  # Use multi-pass burst pattern
  pattern :burst

  # Mutate body with structure-preserving JSON rule
  scope :body, bytes: 16.. do
    preserve :json
  end

  # Post-mutation fixup hook: update 4-byte big-endian payload length at header offset 0
  fixup do |buffer|
    next if buffer.size < 16
    payload_len = (buffer.size - 16).to_u32
    IO::ByteFormat::BigEndian.encode(payload_len, buffer[0, 4])
  end
end

header = Bytes.new(16, 0_u8)
json_payload = %({"status": "active", "code": 200, "meta": {"debug": false}}).to_slice
packet = IO::Memory.new
packet.write(header)
packet.write(json_payload)

sample_packet = packet.to_slice
puts "=== Original Packet (#{sample_packet.size} bytes) ==="
puts sample_packet.inspect
puts ""

puts "=== Generating 5 Mutated Packets ==="
5.times do |i|
  mutant = fuzzer.fuzz(sample_packet)
  header_len = IO::ByteFormat::BigEndian.decode(UInt32, mutant[0, 4])
  actual_body_len = mutant.size - 16
  puts "[#{i + 1}] Total: #{mutant.size} B | Header Len: #{header_len} B | Actual Body: #{actual_body_len} B"
  puts "    Body JSON: #{String.new(mutant[16..])}"
end
