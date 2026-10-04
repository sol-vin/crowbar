require "../src/crowbar"
require "digest/crc32"

puts "=== Crowbar Declarative Framing & Grammar Fuzzer ==="
puts ""

# 1. Context-Free Generative Grammar
# Generates valid SQL query statements with bounded recursion depth
grammar_fuzzer = Crowbar.define do
  seed 42_u64

  grammar :query, max_depth: 5 do
    rule :start, ["SELECT ", :cols, " FROM ", :table, :where_clause]
    rule :cols, ["*"], weight: 0.25
    rule :cols, [:col, ", ", :cols], weight: 0.75
    choices :col, ["id", "username", "email", "balance", "created_at"]
    choices :table, ["users", "accounts", "audit_log", "orders"]
    rule :where_clause, [" WHERE ", :condition], weight: 0.7
    rule :where_clause, [""], weight: 0.3
    rule :condition, [:col, " ", :op, " ", :val]
    choices :op, ["=", "!=", ">", "<", " LIKE "]
    choices :val, ["0", "1", "100", "'admin'", "'active'"]
  end
end

puts "--- 1. Generated Seeds from Grammar ---"
5.times do |i|
  seed_sql = grammar_fuzzer.generate(:query)
  puts "[#{i + 1}] #{seed_sql}"
end
puts ""

# 2. Declarative Protocol Frame
# Models binary packet with auto-updating length and CRC32
frame_fuzzer = Crowbar.define do
  seed 1337_u64

  frame :sensor_packet do
    field :magic, default: Bytes[0xAA, 0x55], mutate: false
    field :version, kind: :u8, default: 1_u8, mutate: false
    field :length, kind: :u16_be, relates_to: :payload
    field :payload, default: "TEMP=24.5C;PRESSURE=1013HPA"
    field :checksum, kind: :crc32
  end

  evolution do
    enabled true
    use_bandit true # Enable UCB1 Multi-Armed Bandit credit assignment
  end
end

puts "--- 2. Fuzzing Declarative Binary Frame ---"
frame = frame_fuzzer.frames["sensor_packet"]
baseline = frame.build_baseline
puts "Baseline Packet Size: #{baseline.size} B"
stored_crc = IO::ByteFormat::BigEndian.decode(UInt32, baseline[(baseline.size - 4), 4])
puts "Baseline CRC32: 0x#{stored_crc.to_s(16).upcase.rjust(8, '0')}"
puts ""

5.times do |i|
  mutant = frame_fuzzer.fuzz_frame(:sensor_packet)
  stored_len = IO::ByteFormat::BigEndian.decode(UInt16, mutant[3, 2])
  stored_crc = IO::ByteFormat::BigEndian.decode(UInt32, mutant[(mutant.size - 4), 4])
  actual_crc = Digest::CRC32.checksum(mutant[0...(mutant.size - 4)])
  crc_valid = (stored_crc == actual_crc)

  puts "[#{i + 1}] Size: #{mutant.size} B | Payload: #{stored_len} B | CRC32: 0x#{stored_crc.to_s(16).upcase.rjust(8, '0')} (Auto-synced: #{crc_valid})"

  # Report feedback to evolutionary bandit
  fitness = mutant.size.to_f64 + (crc_valid ? 50.0 : 0.0)
  frame_fuzzer.report(mutant, fitness: fitness, feature: "PAYLOAD_LEN_#{stored_len}")
end

puts ""
puts "Bandit Arms Evaluated: #{frame_fuzzer.evolution.bandit.arms.size}"
puts "Feature Buckets in Corpus: #{frame_fuzzer.evolution.corpus.feature_buckets.size}"
