require "../src/crowbar"

# Demonstrates Crowbar's Feedback-Driven Evolutionary Mode
# Callers evaluate each candidate and report fitness back to the engine.

fuzzer = Crowbar.define do
  seed 1337_u64

  evolution do
    enabled true
    population_size 32
    crossover_rate 0.3
    exploration_rate 0.15 # 15% random exploration to prevent stagnation
    stagnation_limit 50
  end
end

baseline = "SELECT id, name FROM users WHERE age > 18"
puts "Baseline Input: #{baseline}"
puts "Goal: Evolve inputs that maximize length and character diversity"
puts ""

100.times do |iter|
  candidate = fuzzer.fuzz(baseline)

  # Objective fitness function: length + unique byte count
  unique_chars = candidate.to_slice.to_set.size.to_f64
  fitness = (candidate.size.to_f64 * 0.5) + (unique_chars * 2.0)

  fuzzer.report(candidate, fitness: fitness)

  if (iter + 1) % 25 == 0
    best = fuzzer.evolution.corpus.best
    puts "Iteration #{iter + 1}: Best Fitness = #{best ? best.fitness.round(2) : 0.0} (Size: #{best ? best.buffer.size : 0} B)"
  end
end

puts ""
if best = fuzzer.evolution.corpus.best
  puts "Final Best Candidate:"
  puts best.buffer.to_s
end
