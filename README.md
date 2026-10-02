<div align="center">

<img src="crowbar.gif" alt="Crowbar Banner" width="480" />

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
- 📐 **Structure-Preserving Rules (10 Formats)**:
  - **`JSON`**: Mutates AST leaf nodes (numbers, strings, booleans, arrays, keys) while guaranteeing 100% syntactically valid JSON output.
  - **`YAML`**: Transforms scalar values and mappings while preserving document hierarchy and indentation.
  - **`HTTP`**: Mutates headers, query strings, and body payloads while maintaining strict RFC 7230 CRLF framing.
  - **`DNS`**: Wire-format DNS packet mutations (RFC 1035) preserving 12-byte headers and length-prefixed domain labels.
  - **`CSV`**: Tabular record mutations, column swapping/dropping, quote boundaries, and ragged row injection.
  - **`XML`**: AST-level XML/HTML tree manipulation, attribute fuzzing, and CDATA wrapping.
  - **`URL`**: RFC 3986 URI/URL path traversal, query parameter pollution, and port boundaries.
  - **`TLV`**: Type-Length-Value frames with length under/over-reporting and tag corruption.
  - **`Base64`**: Transparent decode-mutate-encode Base64 envelope transformations.
  - **`Varint`**: LEB128/Protobuf 7-bit continuation bit integer stream boundaries.
- 🎯 **Fine-Grained Selectors & Combinators**: Target byte ranges (`scope :header, bytes: 0...16`), columns (`field: 1`), character classes (`chars: :digits`), periodic strides (`stride: 4`), Shannon entropy (`entropy: :high`), or combine with `&`, `|`, and `~`.
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
# Transform data flowing through a pipe while preserving JSON syntax
echo '{"user": "alice", "age": 30, "admin": false}' | bin/crowbar --rule json -s 42
```

**Output:**
```json
{"user":"32767","age":30,"admin":false}
```

### 2. Opal TrueColor Hex Diff

```bash
# Visually inspect byte-level differences directly in your terminal
echo '{"hello": "world"}' | bin/crowbar --diff --seed 42
```

**Output:**
```text
=== Crowbar Hex Diff ===
Original Size: 19 B | Mutated Size: 29 B
----------------------------------------------------------------
00000000: 7B 22 68 34 32 39 34 39  36 37 32 39 35 65 6C 6C  |{"h4294967295ell|
00000010: 6F 22 3A 20 22 77 6F 72  6C 64 22 7D 0A           |o": "world"}.   |
----------------------------------------------------------------
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

**Output:**
```text
=== Crowbar Component Catalog ===

Structure-Preserving Rules (10 Formats):
  json       Valid JSON AST with mutated leaf values and bounds
  yaml       Valid YAML document hierarchy with mutated scalars
  http       RFC HTTP/1.x framing with mutated headers, paths, or body
  dns        RFC 1035 wire-format DNS packets with mutated records
  csv        RFC 4180 CSV/TSV tabular data with column and cell transforms
  xml        Valid XML/HTML document tree with mutated nodes and attributes
  url        RFC 3986 URI/URL and query string parameters
  tlv        Type-Length-Value binary packet framing and boundary lengths
  base64     Transparent Base64 envelope decode-mutate-encode
  varint     LEB128/Protobuf 7-bit continuation bit integer streams

Mutation Patterns:
  od, once   - Mutate once at a single target
  nd, many   - Mutate multiple times with geometric probability decay (default)
  bu, burst  - Mutate in localized burst clusters
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

**Output:**
```text
The quick brown fox jumps 4294967295over the lazy dog 12345
```

### 2. Structured Protocol Framing & Length Fixups

```crystal
require "crowbar"

# Modernized protocol fuzzer: 16-byte binary header + JSON body
fuzzer = Crowbar.define do
  seed 42_u64

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

header = Bytes.new(16, 0_u8)
json_payload = %({"status": "active", "code": 200, "meta": {"debug": false}}).to_slice
packet = IO::Memory.new
packet.write(header)
packet.write(json_payload)

mutant = fuzzer.fuzz(packet.to_slice)
```

**Output:**
```text
[1] Total: 68 B | Header Len: 52 B | Actual Body: 52 B
    Body JSON: {"status":"32767","code":200,"meta":{"debug":false}}
[2] Total: 63 B | Header Len: 47 B | Actual Body: 47 B
    Body JSON: {"status":"","code":200,"meta":{"debug":false}}
[3] Total: 89 B | Header Len: 73 B | Actual Body: 73 B
    Body JSON: {"status":"active","code":200,"meta":{"debug":false,"debug_extra":false}}
[4] Total: 58 B | Header Len: 42 B | Actual Body: 42 B
    Body JSON: {"status":"active","meta":{"debug":false}}
[5] Total: 86 B | Header Len: 70 B | Actual Body: 70 B
    Body JSON: {"status":"active","code":200,"meta":{"debug":false},"code_extra":200}
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

100.times do
  candidate = fuzzer.fuzz(baseline)

  # Evaluate candidate with your target program or parser
  fitness = evaluate_target_coverage(candidate)

  # Report feedback to guide subsequent generations
  fuzzer.report(candidate, fitness: fitness)
end
```

**Output:**
```text
Baseline Input: SELECT id, name FROM users WHERE age > 18
Goal: Evolve inputs that maximize length and character diversity

Iteration 25: Best Fitness = 515.0 (Size: 810 B)
Iteration 50: Best Fitness = 661.0 (Size: 1102 B)
Iteration 75: Best Fitness = 1215.5 (Size: 2191 B)
Iteration 100: Best Fitness = 2318.0 (Size: 4384 B)
```

---

## Practical Runnable Examples

The repository includes runnable, documented example programs under [`examples/`](examples) showcasing real-world testing workflows:

### 1. Structured JSON Protocol Fuzzer (`examples/json_protocol_fuzzer.cr`)
Fuzzes a compound packet featuring a 16-byte binary header followed by a JSON payload. Employs `preserve :json` within a scoped byte range to guarantee valid JSON syntax while mutating AST nodes, paired with a `fixup` hook that updates the 4-byte big-endian header length field.

```bash
crystal run examples/json_protocol_fuzzer.cr
```

**Output:**
```text
=== Original Packet (75 bytes) ===
Bytes[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 123, 34, 115, 116, 97, 116, 117, 115, 34, 58, 32, 34, 97, 99, 116, 105, 118, 101, 34, 44, 32, 34, 99, 111, 100, 101, 34, 58, 32, 50, 48, 48, 44, 32, 34, 109, 101, 116, 97, 34, 58, 32, 123, 34, 100, 101, 98, 117, 103, 34, 58, 32, 102, 97, 108, 115, 101, 125, 125]

=== Generating 5 Mutated Packets ===
[1] Total: 68 B | Header Len: 52 B | Actual Body: 52 B
    Body JSON: {"status":"32767","code":200,"meta":{"debug":false}}
[2] Total: 63 B | Header Len: 47 B | Actual Body: 47 B
    Body JSON: {"status":"","code":200,"meta":{"debug":false}}
[3] Total: 89 B | Header Len: 73 B | Actual Body: 73 B
    Body JSON: {"status":"active","code":200,"meta":{"debug":false,"debug_extra":false}}
[4] Total: 58 B | Header Len: 42 B | Actual Body: 42 B
    Body JSON: {"status":"active","meta":{"debug":false}}
[5] Total: 86 B | Header Len: 70 B | Actual Body: 70 B
    Body JSON: {"status":"active","code":200,"meta":{"debug":false},"code_extra":200}
```

### 2. Feedback-Driven Genetic Evolution (`examples/genetic_evolution_demo.cr`)
Uses genetic search (tournament selection, crossover splicing, and $\epsilon$-greedy exploration) to iteratively evolve inputs toward maximizing fitness metrics and exploring deeper code paths.

```bash
crystal run examples/genetic_evolution_demo.cr
```

**Output:**
```text
Baseline Input: SELECT id, name FROM users WHERE age > 18
Goal: Evolve inputs that maximize length and character diversity

Iteration 25: Best Fitness = 515.0 (Size: 810 B)
Iteration 50: Best Fitness = 661.0 (Size: 1102 B)
Iteration 75: Best Fitness = 1215.5 (Size: 2191 B)
Iteration 100: Best Fitness = 2318.0 (Size: 4384 B)
```

### 3. HTTP/1.x Request Fuzzer (`examples/http_request_fuzzer.cr`)
Demonstrates structure-preserving HTTP/1.x mutation (`preserve :http`). Generates path traversal injections (`/../`), duplicate headers, and boundary numeric values while strictly preserving RFC 7230 CRLF message framing.

```bash
crystal run examples/http_request_fuzzer.cr
```

**Output:**
```text
=== Original HTTP Request ===
POST /api/v1/auth/login?redirect=/dashboard HTTP/1.1
Host: api.example.com
User-Agent: Crowbar/1.0
Content-Type: application/json
Content-Length: 35

{"user": "admin", "token": "secret"}
=============================

=== Generating 4 Mutated HTTP Requests ===
--- [Mutant #1] ---
POST /api/v1/auth/login?redirect=/dashboard/../2 HTTP/1.1
Host: api.example.com
User-Agent: Crowbar/1.0
Content-Type: application/json
Content-Length: 35

{"user": "admin", "token": "secret"}
-------------------------
--- [Mutant #2] ---
POST /api/v1/auth/login?redirect=/dashboard HTTP/1.1
Host: api.example.com
User-Agent: Crowbar/1.0
Content-Type: application/json
Content-Type: application/json
Content-Length: 35

{"user": "admin", "token": "secret"}
-------------------------
--- [Mutant #3] ---
POST /api/v1/auth/login?redirect=/dashboard HTTP/1.1
Host: 1e-308
User-Agent: Crowbar/1.0
Content-Type: application/json
Content-Length: 35

{"user": "admin", "token": "secret"}
```

### 4. Tabular CSV Pipeline Fuzzer (`examples/csv_pipeline_fuzzer.cr`)
Mutates CSV records while preserving valid tabular syntax (`preserve :csv`). Swaps columns, alters numeric balances, injects boundary values, and verifies outputs against Crystal's `CSV.parse`.

```bash
crystal run examples/csv_pipeline_fuzzer.cr
```

**Output:**
```text
=== Original CSV Dataset ===
id,account_name,balance,status
1001,alice_corp,45000.75,active
1002,bob_holdings,120.00,pending
1003,carol_ventures,-500.25,suspended
1004,david_tech,0.00,active
============================

=== Generating 4 Mutated CSV Datasets ===
--- [Mutant #1] ---
id,account_name,balance,status
1001,alice_corp,45000.75,active
1002,bob_holdings,120.00,pending
1003,carol_ventures,-500.25,suspended,0.0
1004,david_tech,0.00,active

--> Verified: Valid CSV with 5 rows, 4 columns
-------------------------
--- [Mutant #2] ---
id,id,account_name,balance,status
1001,1001,alice_corp,45000.75,active
1002,1002,bob_holdings,120.00,pending
1003,1003,carol_ventures,-500.25,suspended
1004,1004,david_tech,0.00,active

--> Verified: Valid CSV with 5 rows, 5 columns
```

### 5. Binary Telemetry Packet with CRC32 Recalculation (`examples/binary_packet_crc_fuzzer.cr`)
Simulates wire-protocol fuzzing on a packed binary frame (`[Magic: 2B][MsgType: 1B][Length: 2B][Payload: NB][CRC32: 4B]`). Scopes mutation exclusively to the payload (`scope :payload, bytes: 5...-4`) and uses a `fixup` hook to recalculate both payload length and the IEEE 802.3 CRC32 checksum dynamically.

```bash
crystal run examples/binary_packet_crc_fuzzer.cr
```

**Output:**
```text
=== Original Telemetry Packet (56 bytes) ===
Hex: aa5501002f4445564943455f5354415455533a54454d503d32342e35433b46414e3d3132303052504d3b564f4c543d31322e315676f3bc89
CRC32: 0x76F3BC89
=========================================================

=== Generating 5 Mutated Packets with Recomputed CRC32 ===
[1] Size: 394 B | Payload: 385 B | CRC32: 0x9468793C (Verified: true)
[2] Size: 92 B  | Payload: 83 B  | CRC32: 0xBAEE10CA (Verified: true)
[3] Size: 64 B  | Payload: 55 B  | CRC32: 0x00D82B6C (Verified: true)
[4] Size: 70 B  | Payload: 61 B  | CRC32: 0x99C502D1 (Verified: true)
[5] Size: 56 B  | Payload: 47 B  | CRC32: 0xFE2956CF (Verified: true)
```

---

## Component Reference

### Structure-Preserving Rules (10 Formats)
| Rule | Format | Strategy |
| :--- | :--- | :--- |
| `json` | JSON Documents | Traverses AST; mutates leaf numbers, strings, keys, and arrays |
| `yaml` | YAML Documents | Preserves document indentation; mutates scalar nodes |
| `http` | HTTP/1.x Messages | Preserves RFC CRLF framing; mutates paths, headers, or body |
| `dns`  | DNS Wire Packets | Preserves 12-byte header and RFC 1035 length-prefixed domain labels |
| `csv`  | CSV/TSV Tabular | Preserves tabular grid; mutates cells, swaps/duplicates columns, ragged rows |
| `xml`  | XML/HTML Documents | Traverses XML DOM; mutates text nodes, attributes, namespaces, CDATA |
| `url`  | URI / Query Strings | Mutates paths, traversal (`../`), query parameters, and port numbers |
| `tlv`  | TLV Binary Frames | Mutates Type-Length-Value frames, length fields, and payload bytes |
| `base64` | Base64 Envelopes | Transparently decodes, applies binary mutations, and re-encodes |
| `varint` | LEB128 Varints | Mutates 7-bit continuation integers, boundary limits, and overlong bytes |

### Mutation Patterns
| Pattern | ID | Description |
| :--- | :--- | :--- |
| `once`  | `od` | Apply exactly one mutation |
| `many`  | `nd` | Apply one or more mutations with geometric probability decay (default) |
| `burst` | `bu` | Apply a localized cluster of several changes |

### Mutator Arsenal (30 Tools)
| Name | ID | Category | Description |
| :--- | :--- | :--- | :--- |
| `ByteDrop` | `bd` | Byte | Drop a single random byte |
| `ByteFlip` | `bf` | Byte | Flip 1-4 bits in a random byte |
| `ByteInsert` | `bi` | Byte | Insert a random byte at a random position |
| `ByteRepeat` | `br` | Byte | Repeat a byte multiple times (log distribution) |
| `BytePermute` | `bp` | Byte | Permute a contiguous window of adjacent bytes |
| `ByteIncDec` | `bei` | Byte | Increment or decrement a byte value mod 256 |
| `ByteRandom` | `ber` | Byte | Replace a byte with a uniform random value |
| `BitFlipRun` | `bfr` | Bit | Flip a contiguous run of 2 to 32 bits across byte boundaries |
| `WalkingBit` | `wb` | Bit | Slide an inverted single bit through target byte window |
| `SequenceRepeat` | `sr` | Sequence | Repeat a sequence of bytes |
| `SequenceDelete` | `sd` | Sequence | Delete a sequence of bytes |
| `SequenceSwap` | `ss` | Sequence | Swap two disjoint sequences of bytes |
| `LineDelete` | `ld` | Line | Delete a line in text-based data |
| `LineDuplicate` | `lr2` | Line | Duplicate a line in text-based data |
| `LineSwap` | `ls` | Line | Swap two lines in text-based data |
| `LinePermute` | `lp` | Line | Permute a contiguous group of lines |
| `TreeDelete` | `td` | Tree | Delete a balanced delimited node `()`, `[]`, `{}`, `<>`, `""`, `''` |
| `TreeDuplicate` | `tr2` | Tree | Duplicate a balanced delimited node |
| `TreeSwap` | `ts1` | Tree | Swap two balanced delimited nodes |
| `TreeStutter` | `tr` | Tree | Repeat a balanced delimited node multiple times |
| `BoundaryNumbers` | `num` | Values | Mutate textual numbers to boundary values or off-by-one |
| `UnicodeEdgeCases` | `ui` | Values | Inject Unicode boundaries, BOMs, surrogates, and BiDi controls |
| `WhitespaceDelimiters` | `wd` | Values | Vary whitespace formatting, line breaks (CRLF/LF), and null characters |
| `ArithmeticScaler` | `scale` | Arithmetic | Scale numbers by factors (2x, 10x, 100x, 0.5x, bit-shifts) |
| `TimestampMutator` | `time` | Arithmetic | Inject temporal epoch boundaries (Y2038, zero epoch, leap days) |
| `CaseFlip` | `cf` | Text | Invert or alternate case (test case-folding and normalization) |
| `HomoglyphMutator` | `homo` | Text | Substitute ASCII letters with confusable Unicode homoglyphs |
| `DictionaryMutator` | `dict` | Text | Insert or replace tokens using vocabulary dictionary |
| `PaddingMutator` | `pad` | Layout | Inject null, whitespace, or alignment padding |
| `TruncationMutator` | `trunc` | Layout | Truncate buffer at logical line, delimiter, or random offset |

### Selectors & Combinators
| Selector | Syntax | Description |
| :--- | :--- | :--- |
| `ByteRange` | `bytes: 0...16` | Static byte index range |
| `Header` / `Footer` | `header: 16` / `footer: 8` | Prefix or suffix byte slices |
| `DelimitedField` | `field: 1, delimiter: ','` | N-th column or token in delimited records |
| `CharacterClass` | `chars: :digits` | Contiguous digits, hex, alpha, or printable runs |
| `Stride` | `stride: 4, offset: 0` | Periodic byte slices at regular intervals |
| `Entropy` | `entropy: :high` | Shannon entropy slices (:high or :low) |
| `JSONKeyPath` | `json_key: "age"` | Byte offsets of specific JSON keys or values |
| `XMLTag` | `xml_tag: "title"` | Inner contents or elements for XML/HTML tags |
| `Combinators` | `sel_a & sel_b`, `\|`, `~` | Logical intersection, union, and inversion |

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
