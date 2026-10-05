require "./base"
require "./json"
require "./yaml"
require "./http"
require "./dns"
require "./csv"
require "./xml"
require "./url"
require "./tlv"
require "./base64"
require "./varint"
require "./ftp"
require "./sql"
require "./png"
require "./bmp"
require "./wav"
require "./mp3"
require "./wad"
require "./pdf"
require "./seven_zip"
require "./tar"
require "./zip"
require "./packet"
require "./markdown"

module Crowbar::Rules
  # Metadata and factory definition for a registered structure rule
  record Entry,
    name : String,
    description : String,
    aliases : Array(String),
    factory : Proc(Rule) do
    include JSON::Serializable
    @[JSON::Field(ignore: true)]
    getter factory : Proc(Rule) = -> { raise "uninitialized" }
  end

  # Central registry for discovering, aliasing, and instantiating format rules.
  class Registry
    @@entries = Hash(String, Entry).new
    @@alias_map = Hash(String, String).new

    # Registers a rule with its canonical name, description, aliases, and builder factory
    def self.register(name : String, description : String, aliases : Array(String) = [] of String, &block : -> Rule)
      canonical = name.downcase
      entry = Entry.new(canonical, description, aliases.map(&.downcase), block)
      @@entries[canonical] = entry
      @@alias_map[canonical] = canonical
      aliases.each do |a|
        @@alias_map[a.downcase] = canonical
      end
    end

    # Instantiates a rule by canonical name or alias. Returns nil if unknown.
    def self.create?(name : String) : Rule?
      canonical = @@alias_map[name.downcase]?
      return nil unless canonical
      entry = @@entries[canonical]?
      return nil unless entry
      entry.factory.call
    end

    # Instantiates a rule by canonical name or alias. Raises ArgumentError if unknown.
    def self.create!(name : String) : Rule
      create?(name) || raise ArgumentError.new("Unknown rule '#{name}'")
    end

    # Checks whether a given name or alias is registered
    def self.exists?(name : String) : Bool
      @@alias_map.has_key?(name.downcase)
    end

    # Returns the canonical name for an alias or name
    def self.canonical_name(name : String) : String?
      @@alias_map[name.downcase]?
    end

    # Returns all registered rule entries in order of registration
    def self.catalog : Array(Entry)
      @@entries.values
    end

    # Returns all canonical rule names
    def self.names : Array(String)
      @@entries.keys
    end
  end

  # Register standard built-in rules
  Registry.register("json", "Valid JSON AST with mutated leaf values and bounds", [] of String) { JSONRule.new }
  Registry.register("yaml", "Valid YAML document hierarchy with mutated scalars", ["yml"]) { YAMLRule.new }
  Registry.register("http", "RFC HTTP/1.x framing with mutated headers, paths, or body", [] of String) { HTTPRule.new }
  Registry.register("dns", "RFC 1035 wire-format DNS packets with mutated records", [] of String) { DNSRule.new }
  Registry.register("csv", "RFC 4180 CSV/TSV tabular data with column and cell transforms", ["tsv"]) { CSVRule.new }
  Registry.register("xml", "Valid XML/HTML document tree with mutated nodes and attributes", ["html"]) { XMLRule.new }
  Registry.register("url", "RFC 3986 URI/URL and query string parameters", ["uri"]) { URLRule.new }
  Registry.register("tlv", "Type-Length-Value binary packet framing and boundary lengths", [] of String) { TLVRule.new }
  Registry.register("base64", "Transparent Base64 envelope decode-mutate-encode", ["b64"]) { Base64Rule.new }
  Registry.register("varint", "LEB128/Protobuf 7-bit continuation bit integer streams", ["leb"]) { VarintRule.new }
  Registry.register("ftp", "RFC 959 FTP command and response streams with CRLF framing", [] of String) { FTPRule.new }
  Registry.register("sql", "Structure-preserving SQL statement with mutated literals & operators", [] of String) { SQLRule.new }
  Registry.register("png", "Portable Network Graphics with automatic chunk framing & CRC32 recalculation", [] of String) { PNGRule.new }
  Registry.register("bmp", "Windows Bitmap (BMP) with header dimensions, compression & pixel rasters", [] of String) { BMPRule.new }
  Registry.register("wav", "RIFF/WAVE audio streams with fmt parameters, channels & PCM samples", [] of String) { WAVRule.new }
  Registry.register("mp3", "MPEG Layer III audio with ID3v2 tags and synchronized frame headers", [] of String) { MP3Rule.new }
  Registry.register("wad", "Doom WAD directory tables, lump metadata, and THINGS/LINEDEFS payloads", [] of String) { WADRule.new }
  Registry.register("pdf", "Portable Document Format (PDF) objects, dictionaries, streams & xrefs", [] of String) { PDFRule.new }
  Registry.register("7z", "7-Zip archive framing with automated StartHeader CRC32 fixup", ["sevenzip", "7zip", "seven_zip"]) { SevenZipRule.new }
  Registry.register("tar", "POSIX UStar TAR archive framing with automated octal checksum fixup", ["ustar"]) { TarRule.new }
  Registry.register("zip", "PKZip archive framing with automated length and CRC32 fixup", ["pkzip"]) { ZipRule.new }
  Registry.register("packet", "Raw IPv4, TCP, UDP, and PCAP framing with RFC checksum fixups", ["ipv4", "tcp", "udp", "pcap", "rawpacket"]) { PacketRule.new }
  Registry.register("markdown", "CommonMark/Markdown documents with link, table, heading & fence mutations", ["md", "commonmark"]) { MarkdownRule.new }
end

module Crowbar
  alias RuleRegistry = Rules::Registry
end
