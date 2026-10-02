require "../src/crowbar"
require "digest/crc32"

# Crowbar Binary Packet & CRC32 Fixup Fuzzer:
# Protocol Format:
#   [Magic: 2B (0xAA 0x55)]
#   [MsgType: 1B]
#   [PayloadLength: 2B BigEndian]
#   [Payload: N Bytes]
#   [CRC32: 4B BigEndian]
#
# Crowbar mutates internal payload bytes while post-mutation fixups
# automatically recalculate both the payload length field and the CRC32 checksum!

fuzzer = Crowbar.define do
  seed 0xBEEF_u64
  pattern :burst

  # Mutate payload while leaving 5-byte header and 4-byte CRC untouched
  scope :payload, bytes: 5...-4 do
    mutate :bit_flip_run, :byte_inc_dec, :byte_random, :sequence_repeat
  end

  # Fixup hook: update length and recalculate CRC32
  fixup do |buffer|
    next if buffer.size < 9 # 5 header + 4 crc

    # 1. Update 2-byte payload length at offset 3
    payload_len = (buffer.size - 9).to_u16
    IO::ByteFormat::BigEndian.encode(payload_len, buffer[3, 2])

    # 2. Recompute CRC32 across all bytes except the trailing 4-byte checksum
    checksum = Digest::CRC32.checksum(buffer[0...(buffer.size - 4)])
    IO::ByteFormat::BigEndian.encode(checksum, buffer[(buffer.size - 4), 4])
  end
end

# Build baseline packet
magic = Bytes[0xAA_u8, 0x55_u8]
msg_type = Bytes[0x01_u8]
payload = "DEVICE_STATUS:TEMP=24.5C;FAN=1200RPM;VOLT=12.1V".to_slice
payload_len = Bytes.new(2)
IO::ByteFormat::BigEndian.encode(payload.size.to_u16, payload_len)

packet_body = IO::Memory.new
packet_body.write(magic)
packet_body.write(msg_type)
packet_body.write(payload_len)
packet_body.write(payload)

crc = Digest::CRC32.checksum(packet_body.to_slice)
crc_bytes = Bytes.new(4)
IO::ByteFormat::BigEndian.encode(crc, crc_bytes)
packet_body.write(crc_bytes)

sample_packet = packet_body.to_slice
puts "=== Original Telemetry Packet (#{sample_packet.size} bytes) ==="
puts "Hex: #{sample_packet.hexstring}"
puts "CRC32: 0x#{crc.to_s(16).upcase.rjust(8, '0')}"
puts "========================================================="
puts ""

puts "=== Generating 5 Mutated Packets with Recomputed CRC32 ==="
5.times do |i|
  mutant = fuzzer.fuzz(sample_packet)
  stored_len = IO::ByteFormat::BigEndian.decode(UInt16, mutant[3, 2])
  stored_crc = IO::ByteFormat::BigEndian.decode(UInt32, mutant[(mutant.size - 4), 4])
  actual_crc = Digest::CRC32.checksum(mutant[0...(mutant.size - 4)])
  crc_matches = (stored_crc == actual_crc)

  puts "[#{i + 1}] Size: #{mutant.size} B | Payload: #{stored_len} B | CRC32: 0x#{stored_crc.to_s(16).upcase.rjust(8, '0')} (Verified: #{crc_matches})"
  puts "    Hex: #{mutant.to_slice.hexstring}"
end
