# CARBON CHANGELOG
## [0.1.29] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)
- ✦ **[SPEC]** add comprehensive end-to-end CLI integration specs covering all features (`e69b414`)
- ✦ **[CLI]** modularize CLI architecture, add RuleRegistry, JSON modes, and property-based test suites (`02e5fa7`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)
- ✓ **[CLI]** align LibC PollFD and opal_poll with Opal definitions (`ee85f27`)
- ✓ **[RULES]** prevent no-op mutations in HTTPRule (`e7bfcf5`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`28f45e8`)
- 📖 **[CHANGELOG]** record HTTPRule fix (`aa5d612`)

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
## [0.1.28] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)
- ✦ **[SPEC]** add comprehensive end-to-end CLI integration specs covering all features (`e69b414`)
- ✦ **[CLI]** modularize CLI architecture, add RuleRegistry, JSON modes, and property-based test suites (`02e5fa7`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)
- ✓ **[CLI]** align LibC PollFD and opal_poll with Opal definitions (`ee85f27`)
- ✓ **[RULES]** prevent no-op mutations in HTTPRule (`e7bfcf5`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`28f45e8`)
- 📖 **[CHANGELOG]** record HTTPRule fix (`aa5d612`)

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
## [0.1.27] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)
- ✦ **[SPEC]** add comprehensive end-to-end CLI integration specs covering all features (`e69b414`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)
- ✓ **[CLI]** align LibC PollFD and opal_poll with Opal definitions (`ee85f27`)
- ✓ **[RULES]** prevent no-op mutations in HTTPRule (`e7bfcf5`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`28f45e8`)

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
## [0.1.26] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)
- ✦ **[SPEC]** add comprehensive end-to-end CLI integration specs covering all features (`e69b414`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)
- ✓ **[CLI]** align LibC PollFD and opal_poll with Opal definitions (`ee85f27`)
- ✓ **[RULES]** prevent no-op mutations in HTTPRule (`e7bfcf5`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`28f45e8`)

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
## [0.1.25] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)
- ✦ **[SPEC]** add comprehensive end-to-end CLI integration specs covering all features (`e69b414`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)
- ✓ **[CLI]** align LibC PollFD and opal_poll with Opal definitions (`ee85f27`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`57208bb`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`28f45e8`)

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
## [0.1.24] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)
- ✦ **[SPEC]** add comprehensive end-to-end CLI integration specs covering all features (`e69b414`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)
- ✓ **[CLI]** align LibC PollFD and opal_poll with Opal definitions (`ee85f27`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`57208bb`)
- 📖 **[CHANGELOG]** record end-to-end CLI integration specs (`28f45e8`)

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
## [0.1.23] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)
- ✦ **[SPEC]** add comprehensive end-to-end CLI integration specs covering all features (`e69b414`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)
- ✓ **[CLI]** align LibC PollFD and opal_poll with Opal definitions (`ee85f27`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.22] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)
- ✓ **[CLI]** use Opal LibC.opal_poll for POSIX STDIN polling (`f7bc427`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.21] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)
- ✓ **[CLI]** namespace POSIX poll to CrowbarLibC to resolve symbol collision with Opal (`f0891b3`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.20] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)

### 🐛 Bug Fixes
- ✓ **[CLI]** use POSIX LibC poll for cross-platform STDIN detection (`6a94f50`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.19] - 2026-10-04
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)
- ✦ add stateful session system, structure-preserving media/document rules, and detector (`a0e3aa5`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.18] - 2026-10-04
### ✨ Features & Improvements
- ✦ Stateful `crowbar session` CLI command system with persistent iteration memory, multi-armed bandit reward feedback, and automatic baseline reset
- ✦ Dynamic `crowbar session setup` command to configure active rules, mutator pools, execution patterns, and targeted selector scopes
- ✦ Structure-preserving Doom WAD fuzzer (`WADRule`) preserving 12-byte header, 16-byte lump directory table entries, and structured payloads (THINGS, VERTEXES, LINEDEFS, sound/graphics)
- ✦ Portable Document Format fuzzer (`PDFRule`) preserving indirect object framing, mutating dictionary attributes and stream bodies, with automated `startxref` offset synchronization
- ✦ Structure-preserving media format rules for MP3 (ID3v2 tags & MPEG frame sync words), WAV (RIFF container & fmt headers), PNG (chunk framing & auto-CRC32), and BMP (DIB headers & pixel rasters)
- ✦ Automatic magic-byte and framing format detector (`Crowbar::Detector`) for piped streams across 18 protocols, media, and document formats
- ✦ RFC 959 FTP CRLF stream fuzzer and structure-preserving SQL AST query transformer
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`331b7b9`)

### 🐛 Bug Fixes
- ✓ Cross-platform POSIX STDIN data detection using LibC poll for Linux and macOS

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.17] - 2026-10-02
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`ad3978e`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.17] - 2026-10-02
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`ad3978e`)
- ✦ add CLI & DSL tests, 3 runnable protocol fuzzer examples, and example output in README (`2567dc4`)

### 📚 Documentation
- 📖 add crowbar.gif banner and update component tables in README (`3eae1a6`)

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
## [0.1.16] - 2026-10-01
### ✨ Features & Improvements
- ✦ complete overhaul of Crowbar into modern data transformation, structure-preserving mutation, and evolutionary testing framework (`f27db55`)
- ✦ expand to 10 structure rules, 7 new selectors with combinators, and 9 mutator families (`a860ab0`)

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

