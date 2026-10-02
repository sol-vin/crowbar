# CARBON CHANGELOG
## [0.1.15] - 2026-10-01
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)

### 🛠️ Chores & Tooling
- • 1st commit (`4029cc1`)
- • Readme fix (`32d3894`)
- • More work, still not functional (`cf3c6f5`)
- • Working now (`b3af601`)
- • Added bytes, float to decimal (`361c37c`)
- • Add  bytes generator, add string and char generators (`4ce4497`)
- • Playing with weighting system (`bcca163`)
- • Clean up, fixing read_me (`735df12`)
- • Fixes to range, regex (`0e2b6c6`)
- • Added crowbar mutator (`0d8f467`)
- • Working on xiongmai example fuzzer (`f58e930`)
- • Updated readme (`d869a4e`)
- • Updates (`973ca85`)

---
## [0.1.14] - 2026-10-01
### ✨ Features & Improvements
- ✦ Added 6 new structure-preserving rules for CSV/TSV, XML/HTML, URL/URI, TLV binary frames, Base64 envelopes, and LEB128 varints
- ✦ Added 7 new advanced selectors including DelimitedField, CharacterClass, Stride, Shannon Entropy, JSONKeyPath, XMLTag, and composable combinators (&, |, ~)
- ✦ Added 9 new mutator families covering Bit-Flip Runs (bfr), Walking Bit (wb), Arithmetic Scaler (scale), Timestamp/Epoch Boundaries (time), Case Inversion (cf), Unicode Homoglyphs (homo), Token Dictionary (dict), Padding (pad), and Truncation (trunc)
- ✦ Expanded CLI and Opal component catalog with comprehensive categorization across 10 rules, 30 mutators, patterns, and selectors

### 📚 Documentation
- 📖 Added structure rules and advanced selectors Jasper documentation guide

### 🛠️ Chores & Tooling
- • Readme fix (`32d3894`)
- • More work, still not functional (`cf3c6f5`)
- • Working now (`b3af601`)
- • Added bytes, float to decimal (`361c37c`)
- • Add  bytes generator, add string and char generators (`4ce4497`)
- • Playing with weighting system (`bcca163`)
- • Clean up, fixing read_me (`735df12`)
- • Fixes to range, regex (`0e2b6c6`)
- • Added crowbar mutator (`0d8f467`)
- • Working on xiongmai example fuzzer (`f58e930`)
- • Updated readme (`d869a4e`)
- • Updates (`973ca85`)

---
## [0.1.13] - 2026-10-01
### 💥 Breaking Changes
- ▲ Total modernization and redesign of Crowbar architecture and DSL, removing obsolete 2019 Perlin noise dependencies

### ✨ Features & Improvements
- ✦ Added structure-preserving rules for JSON, YAML, HTTP/1.x, and RFC 1035 DNS wire packets
- ✦ Added feedback-driven evolutionary optimization with population corpus, tournament selection, crossover recombination, and anti-stagnation loop prevention
- ✦ Added deterministic fast 64-bit PRNG (Xoshiro256++) seeded for exact test case reproducibility
- ✦ Added comprehensive Radamsa-inspired mutators across byte, sequence, line, tree, numeric boundary, and Unicode domains
- ✦ Added standalone UNIX streaming filter CLI with Opal TrueColor hex diff display

### 📚 Documentation
- 📖 Added multi-track Jasper documentation guides and full test suite with 100% pass rate

