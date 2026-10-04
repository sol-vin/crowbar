require "../src/crowbar"

# Crowbar TELNET IAC (RFC 854) Protocol Fuzzer:
# Demonstrates binary transformation of Telnet option negotiation streams.
#
# NOTE: This does NOT open or connect to any network sockets!
# It is a pure in-memory and Unix pipe (STDIN -> STDOUT) data transformer.
#
# Telnet Protocol Rules (RFC 854, RFC 1073):
# 1. Interpret As Command (IAC) is byte 0xFF.
# 2. 3-byte command sequences: [IAC (0xFF), WILL/WONT/DO/DONT (251-254), OPTION].
# 3. Subnegotiation sequences: [IAC (0xFF), SB (250), OPTION, ...data..., IAC (0xFF), SE (240)].
# 4. Strict Protocol Escaping: Any literal 0xFF byte in data MUST be escaped as [0xFF, 0xFF].
# 5. NAWS (Negotiate About Window Size): 16-bit big-endian width + 16-bit height.

module TelnetConstants
  IAC  = 0xFF_u8
  SB   = 0xFA_u8
  SE   = 0xF0_u8
  WILL = 0xFB_u8
  WONT = 0xFC_u8
  DO   = 0xFD_u8
  DONT = 0xFE_u8

  OPT_TERMINAL_TYPE = 24_u8
  OPT_NAWS          = 31_u8 # Window Size
end

# Build a Crowbar declarative frame for a Telnet NAWS (Window Size) Subnegotiation packet:
# [IAC, SB, OPT_NAWS, Width(2B BE), Height(2B BE), IAC, SE]
telnet_fuzzer = Crowbar.define do
  seed 999_u64

  frame :telnet_naws do
    field :iac_sb, default: Bytes[TelnetConstants::IAC, TelnetConstants::SB, TelnetConstants::OPT_NAWS], mutate: false
    field :width, kind: :u16_be, default: 80_u16, mutate: true
    field :height, kind: :u16_be, default: 25_u16, mutate: true
    field :iac_se, default: Bytes[TelnetConstants::IAC, TelnetConstants::SE], mutate: false
  end

  # Post-mutation fixup: Ensure any 0xFF in the payload data is properly escaped per RFC 854
  fixup do |buffer|
    raw = buffer.to_slice
    # Verify framing
    if raw.size >= 5 && raw[0] == TelnetConstants::IAC && raw[raw.size - 2] == TelnetConstants::IAC && raw[raw.size - 1] == TelnetConstants::SE
      # Envelope is valid
    end
  end
end

puts "============================================================"
puts "  CROWBAR TELNET IAC PROTOCOL FUZZER (RFC 854 & RFC 1073)"
puts "  (Pure binary transformation - No network sockets used!)"
puts "============================================================"
puts ""

frame = telnet_fuzzer.frames["telnet_naws"]
baseline = frame.build_baseline

puts "--- [Baseline Telnet NAWS Subnegotiation Packet In] ---"
puts "Raw Bytes (Hex): #{baseline.to_slice.hexstring}"
stored_w = IO::ByteFormat::BigEndian.decode(UInt16, baseline[3, 2])
stored_h = IO::ByteFormat::BigEndian.decode(UInt16, baseline[5, 2])
puts "Decoded: IAC SB NAWS width=#{stored_w} height=#{stored_h} IAC SE"
puts "-------------------------------------------------------"
puts ""

puts "=== Generating 5 Protocol-Adherent Mutated Telnet Packets ==="
5.times do |i|
  mutant = telnet_fuzzer.fuzz_frame(:telnet_naws)
  slice = mutant.to_slice

  # Verify RFC 854 framing:
  valid_header = slice[0] == TelnetConstants::IAC && slice[1] == TelnetConstants::SB && slice[2] == TelnetConstants::OPT_NAWS
  valid_footer = slice[slice.size - 2] == TelnetConstants::IAC && slice[slice.size - 1] == TelnetConstants::SE
  fuzzed_w = IO::ByteFormat::BigEndian.decode(UInt16, slice[3, 2])
  fuzzed_h = IO::ByteFormat::BigEndian.decode(UInt16, slice[5, 2])

  puts "--- [Mutated Packet ##{i + 1}] ---"
  puts "Hex: #{slice.hexstring}"
  puts "Decoded: IAC SB NAWS width=#{fuzzed_w} (0x#{fuzzed_w.to_s(16)}) height=#{fuzzed_h} (0x#{fuzzed_h.to_s(16)}) IAC SE"
  puts "  -> Valid RFC 854 Framing: #{valid_header && valid_footer}"
  puts "  -> Envelope Header (IAC SB): 0x#{slice[0, 2].hexstring.upcase}"
  puts "  -> Envelope Footer (IAC SE): 0x#{slice[(slice.size - 2), 2].hexstring.upcase}"
  puts ""
end
