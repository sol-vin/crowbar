require "../src/crowbar"

# Crowbar Custom Defined Protocol Fuzzer: Redis Serialization Protocol (RESP)
# Demonstrates framing adherence for custom text/binary line protocols.
#
# NOTE: This does NOT open or connect to any network sockets!
# It is a pure in-memory and Unix pipe (STDIN -> STDOUT) data transformer.
#
# RESP Protocol Rules:
# - Arrays start with `*<count>\r\n`.
# - Bulk strings start with `$<length>\r\n<bytes>\r\n`.
# - Integers start with `:<number>\r\n`.
# - Simple strings start with `+<string>\r\n`.
# - Strict Framing Constraint: The length prefix `$<length>` MUST exactly match
#   the byte length of `<bytes>` following it, terminated by `\r\n`.

# Build a Crowbar pipeline that mutates RESP arguments while auto-syncing $<length>:
resp_fuzzer = Crowbar.define do
  seed 2026_u64

  # Target bulk string contents using balanced delimiter / newline matching,
  # then apply post-transform fixup to re-synchronize all $<length> headers:
  fixup do |buffer|
    raw = buffer.to_s
    lines = raw.split("\r\n")

    # Pass 1: For any bulk string prefix `$N`, measure the subsequent data line and update `$N`
    i = 0
    updated_lines = [] of String
    while i < lines.size
      line = lines[i]
      if line.starts_with?('$') && (claimed = line[1..].to_i?) && (i + 1) < lines.size
        data_line = lines[i + 1]
        actual_len = data_line.bytesize
        updated_lines << "$#{actual_len}"
        updated_lines << data_line
        i += 2
      else
        updated_lines << line
        i += 1
      end
    end

    reconstructed = updated_lines.join("\r\n")
    buffer.replace_range(0, buffer.size, reconstructed.to_slice)
  end
end

sample_resp_command = "*3\r\n" \
                      "$3\r\nSET\r\n" \
                      "$9\r\nuser:1001\r\n" \
                      "$24\r\n{\"role\": \"admin\", \"v\": 1}\r\n"

puts "============================================================"
puts "  CROWBAR CUSTOM PROTOCOL FUZZER: REDIS RESP"
puts "  (Pure text transformation - No network sockets used!)"
puts "============================================================"
puts ""
puts "--- [Original RESP Command In] ---"
print sample_resp_command
puts "----------------------------------"
puts ""

puts "=== Generating 4 Protocol-Adherent Mutated RESP Commands ==="
4.times do |i|
  # Mutate via Crowbar engine
  mutant = resp_fuzzer.fuzz(sample_resp_command).to_s

  puts "--- [Mutated RESP Command ##{i + 1}] ---"
  print mutant
  puts "----------------------------------"

  # Verify RESP framing rules:
  lines = mutant.split("\r\n").reject(&.empty?)
  all_synced = true
  j = 0
  while j < lines.size
    line = lines[j]
    if line.starts_with?('$') && (claimed = line[1..].to_i?)
      actual_bytes = (j + 1 < lines.size) ? lines[j + 1].bytesize : 0
      if claimed != actual_bytes
        all_synced = false
      end
      j += 2
    else
      j += 1
    end
  end

  puts "  -> Strict CRLF Framing: #{mutant.ends_with?("\r\n")}"
  puts "  -> All Bulk String Lengths ($len) Auto-Synchronized: #{all_synced}"
  puts ""
end
