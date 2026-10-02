require "../src/crowbar"
require "csv"

# Crowbar CSV Pipeline Fuzzer:
# Demonstrates structure-preserving CSV tabular transformation.
# Mutates cells, swaps columns, alters numerical bounds, and injects boundary values.

fuzzer = Crowbar.define do
  seed 98765_u64
  preserve :csv
end

sample_csv = <<-CSV
id,account_name,balance,status
1001,alice_corp,45000.75,active
1002,bob_holdings,120.00,pending
1003,carol_ventures,-500.25,suspended
1004,david_tech,0.00,active
CSV

puts "=== Original CSV Dataset ==="
puts sample_csv
puts "============================"
puts ""

puts "=== Generating 4 Mutated CSV Datasets ==="
4.times do |i|
  mutant = fuzzer.fuzz(sample_csv)
  puts "--- [Mutant ##{i + 1}] ---"
  puts mutant
  begin
    rows = CSV.parse(mutant.to_s)
    puts "--> Verified: Valid CSV with #{rows.size} rows, #{rows.first?.try(&.size) || 0} columns"
  rescue ex
    puts "--> Parser detected format deviation: #{ex.message}"
  end
  puts "-------------------------"
end
