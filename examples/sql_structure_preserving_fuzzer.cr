require "../src/crowbar"

# Crowbar Structure-Preserving SQL Fuzzer:
# Demonstrates SQL query mutation preserving syntactic statement structure
# while injecting boundary numbers, SQL injection probes, and operator variants.
#
# NOTE: This does NOT open or connect to any database or network sockets!
# It is a pure in-memory and Unix pipe (STDIN -> STDOUT) data transformer.
#
# Features demonstrated:
# 1. Structure-preserving SQLRule preserving query skeleton (SELECT, FROM, WHERE, clauses).
# 2. Injection of numeric boundary values (-9223372036854775808, 1e308, 0).
# 3. Injection of string literal probes (' OR '1'='1, null bytes, Unicode homoglyphs).
# 4. Comparison operator mutation (=, !=, <>, LIKE, IN).

sql_fuzzer = Crowbar.define do
  seed 4242_u64
  preserve :sql
end

sample_query = "SELECT id, username, email, balance FROM users " \
               "WHERE status = 'active' AND balance >= 100 " \
               "ORDER BY balance DESC LIMIT 25;"

puts "============================================================"
puts "  CROWBAR STRUCTURE-PRESERVING SQL PIPELINE FUZZER"
puts "  (Pure text transformation - No network sockets used!)"
puts "============================================================"
puts ""
puts "--- [Original SQL Query In] ---"
puts sample_query
puts "-------------------------------"
puts ""

puts "=== Generating 5 Mutated SQL Queries ==="
5.times do |i|
  mutant = sql_fuzzer.fuzz(sample_query).to_s

  # Check keywords preservation:
  has_select = mutant.includes?("SELECT")
  has_from = mutant.includes?("FROM")

  puts "--- [Mutated Query ##{i + 1}] ---"
  puts mutant
  puts "-------------------------------"
  puts "  -> Preserved Statement Structure (SELECT/FROM): #{has_select && has_from}"
  puts ""
end
