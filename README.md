<div align="center">

# Crowbar ⚡
*Next-Generation Data Transformation, Structure-Preserving Mutation & Evolutionary Testing Framework for Crystal*

[![CI](https://github.com/sol-vin/crowbar/actions/workflows/ci.yml/badge.svg)](https://github.com/sol-vin/crowbar/actions/workflows/ci.yml)
[![Crystal](https://img.shields.io/badge/crystal-%3E%3D1.20.0-black.svg)](https://crystal-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-green.svg)](https://sol-vin.github.io/crowbar/)

*Pure Crystal. Zero external C/binary dependencies. Native Windows, Linux, and macOS support.*

</div>

---

## Overview

**Crowbar** is a modern, extensible data transformation, structure-preserving mutation, and feedback-driven test generation engine for [Crystal](https://crystal-lang.org).

Inspired by the versatility of general-purpose mutation engines and modern property-based testing, Crowbar operates both as a **high-throughput UNIX streaming filter** (`cat input | crowbar > output`) and a **deeply customizable, type-safe Crystal DSL**.

### Key Features

- 🧬 **Feedback-Driven Evolutionary Search (Genetic Algorithm)**: Callers can report execution outcomes (`fuzzer.report(candidate, fitness)`) back to the engine. Uses tournament/roulette selection and crossover recombination to evolve inputs toward maximizing coverage and depth.
- 🔄 **Anti-Stagnation & Loop Prevention**: Built-in $\epsilon$-greedy exploration rate (guaranteed fresh random inputs) and novelty injection (automatic local minima clearing) prevents the optimizer from locking into repetitive loops.
- 📐 **Structure-Preserving Rules**:
  - **`JSON`**: Mutates AST leaf nodes (numbers, strings, booleans, arrays, keys) while guaranteeing 100% syntactically valid JSON output.
  - **`YAML`**: Transforms scalar values and mappings while preserving document hierarchy and indentation.
  - **`HTTP`**: Mutates headers, query strings, and body payloads while maintaining strict RFC 7230 CRLF framing.
  - **`DNS`**: Wire-format DNS packet mutations (RFC 1035) preserving 12-byte headers and length-prefixed domain labels.
- 🎯 **Fine-Grained Scopes & Matchers**: Target specific byte ranges (`scope :header, bytes: 0...16`), regex capture groups (`match /"([^"]+)"/, group: 1`), or balanced delimiters (`()`, `[]`, `{}`, `<>`, `""`).
- 🔧 **Post-Transform Fixup Hooks**: Automatically recalculate checksums (CRC32, MD5) or payload length fields after mutating body contents.
- 🎲 **Deterministic PRNG (Xoshiro256++)**: Fast 64-bit random state seeded for exact, reproducible test cases across platforms.
- 🎨 **Opal TrueColor Hex Diff & CLI**: Side-by-side terminal hex diff visualization powered by [Opal](https://github.com/sol-vin/opal).
- 📦 **Automated Versioning & Docs**: Integrated with [Carbon](https://github.com/sol-vin/carbon) for monotonic commit versioning and [Jasper](https://github.com/sol-vin/jasper) for multi-track documentation guides.

---

## Installation

Add Crowbar to your `shard.yml`:

```yaml
dependencies:
  crowbar:
    github: sol-vin/crowbar
    branch: master
```

Then run:

```bash
shards install
```

---

## Quick Start (CLI)

Build the standalone `crowbar` binary:

```bash
shards build crowbar
```

### 1. Pipe-In, Pipe-Out (UNIX Filter Mode)

```bash
# Transform data flowing through a pipe
echo '{"user": "alice", "age": 30}' | bin/crowbar --rule json
```

### 2. Opal TrueColor Hex Diff

```bash
# Visually inspect byte-level differences directly in your terminal
bin/crowbar --diff --seed 42 sample.bin
```

### 3. Batch Test Case Generation

```bash
# Generate 100 deterministic test files from sample inputs
bin/crowbar -n 100 -s 1337 -o "fuzz-%n.bin" samples/*.bin
```

### 4. Component Catalog

```bash
bin/crowbar --list
```

---

## Quick Start (Crystal DSL)

### 1. Zero-Config Black-Box Transformation

```crystal
require "crowbar"

sample = "The quick brown fox jumps over the lazy dog 12345"
mutant = Crowbar.fuzz(sample, seed: 42_u64)
puts mutant
```

### 2. Structured Protocol Framing & Length Fixups

```crystal
require "crowbar"

# Modernized protocol fuzzer: 16-byte binary header + JSON body
fuzzer = Crowbar.define do
  seed 0x1337_u64

  # Use multi-pass burst pattern
  pattern :burst

  # Preserve valid JSON structure in body
  scope :body, bytes: 16.. do
    preserve :json
  end

  # Post-mutation fixup hook: automatically recompute payload length!
  fixup do |buffer|
    next if buffer.size < 16
    payload_len = (buffer.size - 16).to_u32
    IO::ByteFormat::BigEndian.encode(payload_len, buffer[0, 4])
  end
end

sample_packet = File.read("packet.bin").to_slice
mutant = fuzzer.fuzz(sample_packet)
```

### 3. Feedback-Driven Evolutionary Optimization

```crystal
require "crowbar"

fuzzer = Crowbar.define do
  seed 42_u64

  evolution do
    enabled true
    population_size 64
    selection :tournament, size: 4
    crossover_rate 0.25
    exploration_rate 0.15 # 15% random exploration to prevent local loops
    stagnation_limit 100  # Inject fresh entropy after 100 stagnant cycles
  end
end

baseline = "SELECT id, name FROM users WHERE age > 18"

1000.times do
  candidate = fuzzer.fuzz(baseline)

  # Evaluate candidate with your target program or parser
  fitness = evaluate_target_coverage(candidate)

  # Report feedback to guide subsequent generations
  fuzzer.report(candidate, fitness: fitness)
end
```

---

## Component Reference

### Structure-Preserving Rules
| Rule | Format | Strategy |
| :--- | :--- | :--- |
| `json` | JSON Documents | Traverses AST; mutates leaf numbers, strings, keys, and arrays |
| `yaml` | YAML Documents | Preserves document indentation; mutates scalar nodes |
| `http` | HTTP/1.x Messages | Preserves RFC CRLF framing; mutates paths, headers, or body |
| `dns`  | DNS Wire Packets | Preserves 12-byte header and RFC 1035 length-prefixed domain labels |

### Mutation Patterns
| Pattern | ID | Description |
| :--- | :--- | :--- |
| `once`  | `od` | Apply exactly one mutation |
| `many`  | `nd` | Apply one or more mutations with geometric probability decay (default) |
| `burst` | `bu` | Apply a localized cluster of several changes |

### Mutator Families
| Name | ID | Description |
| :--- | :--- | :--- |
| `ByteDrop` | `bd` | Drop a single random byte |
| `ByteFlip` | `bf` | Flip 1-4 bits in a random byte |
| `ByteInsert` | `bi` | Insert a random byte at a random position |
| `ByteRepeat` | `br` | Repeat a byte multiple times (log distribution) |
| `BytePermute` | `bp` | Permute a contiguous window of adjacent bytes |
| `ByteIncDec` | `bei` | Increment or decrement a byte value mod 256 |
| `ByteRandom` | `ber` | Replace a byte with a uniform random value |
| `SequenceRepeat` | `sr` | Repeat a sequence of bytes |
| `SequenceDelete` | `sd` | Delete a sequence of bytes |
| `SequenceSwap` | `ss` | Swap two disjoint sequences of bytes |
| `LineDelete` | `ld` | Delete a line in text-based data |
| `LineDuplicate` | `lr2` | Duplicate a line in text-based data |
| `LineSwap` | `ls` | Swap two lines in text-based data |
| `LinePermute` | `lp` | Permute a contiguous group of lines |
| `TreeDelete` | `td` | Delete a balanced delimited node `()`, `[]`, `{}`, `<>`, `""`, `''` |
| `TreeDuplicate` | `tr2` | Duplicate a balanced delimited node |
| `TreeSwap` | `ts1` | Swap two balanced delimited nodes |
| `TreeStutter` | `tr` | Repeat a balanced delimited node multiple times |
| `BoundaryNumbers` | `num` | Mutate textual numbers to boundary values or off-by-one |
| `UnicodeEdgeCases` | `ui` | Inject Unicode boundaries, BOMs, surrogates, and BiDi controls |
| `WhitespaceDelimiters` | `wd` | Vary whitespace formatting, line breaks (CRLF/LF), and null characters |

---

## Development & Testing

Run the automated test suite:

```bash
crystal spec --verbose
```

Verify formatting:

```bash
crystal tool format --check
```

Build Jasper guides and HTML documentation:

```bash
bin/jasper build
crystal docs
```

Audit version consistency with Carbon:

```bash
bin/carbon check
bin/carbon doctor
```

---

## License

MIT License. Copyright (c) 2019-2026 Ian Rash (sol-vin).
