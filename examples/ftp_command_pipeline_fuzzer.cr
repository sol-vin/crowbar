require "../src/crowbar"

# Crowbar FTP Command & Response Pipeline Fuzzer:
# Demonstrates structure-preserving RFC 959 FTP message stream transformation.
#
# NOTE: This does NOT open or connect to any network sockets!
# It is a pure in-memory and Unix pipe (STDIN -> STDOUT) data transformer.
#
# Features demonstrated:
# 1. Strict RFC 959 CRLF (\r\n) line framing.
# 2. Command verb preservation with argument-specific mutations (PORT octets, RETR paths, USER auth).
# 3. Server response code & status message transforms (e.g. 220, 227 PASV response).

fuzzer = Crowbar.define do
  seed 101_u64

  ftp do
    mutate_responses = true
    mutate_verbs = false # Keep valid RFC verbs intact, mutating arguments
  end
end

sample_ftp_session = "USER administrator\r\n" \
                     "PASS SuperSecretPass123\r\n" \
                     "TYPE I\r\n" \
                     "PORT 192,168,1,100,19,136\r\n" \
                     "RETR accounting_ledger_2026.csv\r\n" \
                     "QUIT\r\n"

puts "============================================================"
puts "  CROWBAR FTP COMMAND PIPELINE FUZZER (RFC 959)"
puts "  (Pure text transformation - No network sockets used!)"
puts "============================================================"
puts ""
puts "--- [Original FTP Command Stream In] ---"
print sample_ftp_session
puts "----------------------------------------"
puts ""

puts "=== Generating 4 Protocol-Adherent Mutated Command Streams ==="
4.times do |i|
  mutant = fuzzer.fuzz(sample_ftp_session).to_s

  lines = mutant.split("\r\n").reject(&.empty?)
  all_crlf = mutant.ends_with?("\r\n")

  puts "--- [Mutated FTP Stream ##{i + 1}] ---"
  print mutant
  puts "----------------------------------------"
  puts "  -> Strict CRLF Line Endings: #{all_crlf}"
  puts "  -> Total Lines Preserved: #{lines.size}"
  port_line = lines.find { |l| l.starts_with?("PORT") }
  if port_line
    puts "  -> Mutated PORT Argument: #{port_line}"
  end
  retr_line = lines.find { |l| l.starts_with?("RETR") }
  if retr_line
    puts "  -> Mutated RETR Argument: #{retr_line}"
  end
  puts ""
end

# Demonstrate FTP Server Response Transformation
sample_ftp_response = "220 ProFTPD 1.3.8 Server (Debian) [127.0.0.1]\r\n" \
                      "331 Password required for administrator\r\n" \
                      "230 User administrator logged in\r\n" \
                      "227 Entering Passive Mode (192,168,1,100,19,136).\r\n"

puts "--- [Original FTP Server Responses In] ---"
print sample_ftp_response
puts "------------------------------------------"
puts ""
puts "--- [Mutated FTP Server Responses Out] ---"
mutated_resp = fuzzer.fuzz(sample_ftp_response).to_s
print mutated_resp
puts "------------------------------------------"
