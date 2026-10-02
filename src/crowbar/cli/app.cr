require "option_parser"
require "opal"
require "../../crowbar"
require "./diff"

module Crowbar::CLI
  class App
    def self.run(args : Array(String) = ARGV)
      new.run(args)
    end

    @count : Int32 = 1
    @seed : UInt64? = nil
    @output_pattern : String? = nil
    @selected_mutations : String? = nil
    @selected_pattern : String? = nil
    @selected_rule : String? = nil
    @show_diff : Bool = false
    @input_files : Array(String) = [] of String

    def run(args : Array(String))
      parser = OptionParser.new do |opts|
        opts.banner = Opal.style.bold.fg(:cyan).render("Crowbar #{Crowbar.version} - Data Transformation & Fuzzing Engine") +
                      "\nUsage: crowbar [options] [sample-files...]"

        opts.on("-n COUNT", "--count COUNT", "Number of test cases to generate (default: 1, -1 for inf)") do |c|
          @count = c.to_i
        end

        opts.on("-s SEED", "--seed SEED", "Deterministic 64-bit random seed") do |s|
          @seed = s.to_u64? || s.hash.to_u64
        end

        opts.on("-o PATTERN", "--output PATTERN", "Output destination: '-' (stdout) or 'out-%n.ext'") do |o|
          @output_pattern = o
        end

        opts.on("-m LIST", "--mutations LIST", "Filter mutators (e.g. bd,bf,num)") do |m|
          @selected_mutations = m
        end

        opts.on("-p PATTERN", "--patterns PATTERN", "Execution pattern: once (od), many (nd), burst (bu)") do |p|
          @selected_pattern = p
        end

        opts.on("-r RULE", "--rule RULE", "Structure-preserving rule: json, yaml, http, dns, csv, xml, url, tlv, base64, varint") do |r|
          @selected_rule = r
        end

        opts.on("-d", "--diff", "Display Opal TrueColor terminal hex diff") do
          @show_diff = true
        end

        opts.on("-l", "--list", "List all available rules, mutators, patterns, and selectors") do
          print_list
          exit 0
        end

        opts.on("-v", "--version", "Print version") do
          puts "Crowbar #{Crowbar.version}"
          exit 0
        end

        opts.on("-h", "--help", "Show help message") do
          puts opts
          exit 0
        end
      end

      parser.parse(args)
      @input_files = args

      # Read input corpus
      input_buffer = read_input

      if input_buffer.empty?
        STDERR.puts Opal.style.fg(:yellow).render("Warning: No input data provided. Supply a sample file or pipe data via STDIN.")
        exit 1
      end

      # Construct engine
      engine = Crowbar::Engine.new(@seed || PRNG.default_seed)

      # Apply pattern if requested
      if pat = @selected_pattern
        case pat
        when "od", "once"  then engine.pattern = Patterns::Once.new
        when "bu", "burst" then engine.pattern = Patterns::Burst.new
        when "nd", "many"  then engine.pattern = Patterns::Many.new
        end
      end

      # Apply rule if requested
      if rule_name = @selected_rule
        case rule_name.downcase
        when "json"          then engine.add_rule(Rules::JSONRule.new)
        when "yaml", "yml"   then engine.add_rule(Rules::YAMLRule.new)
        when "http"          then engine.add_rule(Rules::HTTPRule.new)
        when "dns"           then engine.add_rule(Rules::DNSRule.new)
        when "csv", "tsv"    then engine.add_rule(Rules::CSVRule.new)
        when "xml", "html"   then engine.add_rule(Rules::XMLRule.new)
        when "url", "uri"    then engine.add_rule(Rules::URLRule.new)
        when "tlv"           then engine.add_rule(Rules::TLVRule.new)
        when "base64", "b64" then engine.add_rule(Rules::Base64Rule.new)
        when "varint", "leb" then engine.add_rule(Rules::VarintRule.new)
        end
      end

      # Filter mutators if requested
      if mut_list = @selected_mutations
        names = mut_list.split(",").map(&.strip)
        engine.pool.mutators.clear
        pool = MutatorPool.new
        names.each do |n|
          if m = pool.find?(n)
            engine.pool.register(m)
          end
        end
      end

      # Execution loop
      iteration = 1
      loop do
        mutated = engine.transform(input_buffer)

        if @show_diff
          HexDiff.render(input_buffer, mutated)
        elsif pattern = @output_pattern
          write_output(pattern, mutated, iteration)
        else
          # Default: emit mutated bytes to STDOUT
          STDOUT.write(mutated.to_slice)
        end

        break if @count > 0 && iteration >= @count
        iteration += 1
      end
    end

    private def read_input : Buffer
      if !@input_files.empty?
        # Read from first sample file (or concatenate)
        file_path = @input_files.first
        if File.exists?(file_path)
          Buffer.new(File.read(file_path))
        else
          STDERR.puts "Error: File '#{file_path}' does not exist"
          exit 1
        end
      else
        # Read from STDIN
        Buffer.from_io(STDIN)
      end
    end

    private def write_output(pattern : String, buffer : Buffer, iteration : Int32)
      if pattern == "-"
        STDOUT.write(buffer.to_slice)
      else
        filename = pattern.gsub("%n", iteration.to_s)
        File.write(filename, buffer.to_slice)
      end
    end

    private def print_list
      title_style = Opal.style.bold.fg(:cyan)
      category_style = Opal.style.bold.fg(:yellow)
      dim_style = Opal.style.fg(:bright_black)
      name_style = Opal.style.bold.fg(:green)

      puts title_style.render("=== Crowbar Component Catalog ===")
      puts ""

      puts category_style.render("Structure-Preserving Rules (10 Formats):")
      rules = [
        {"json", "Valid JSON AST with mutated leaf values and bounds"},
        {"yaml", "Valid YAML document hierarchy with mutated scalars"},
        {"http", "RFC HTTP/1.x framing with mutated headers, paths, or body"},
        {"dns", "RFC 1035 wire-format DNS packets with mutated records"},
        {"csv", "RFC 4180 CSV/TSV tabular data with column and cell transforms"},
        {"xml", "Valid XML/HTML document tree with mutated nodes and attributes"},
        {"url", "RFC 3986 URI/URL and query string parameters"},
        {"tlv", "Type-Length-Value binary packet framing and boundary lengths"},
        {"base64", "Transparent Base64 envelope decode-mutate-encode"},
        {"varint", "LEB128/Protobuf 7-bit continuation bit integer streams"},
      ]
      rules.each do |(code, desc)|
        puts sprintf("  %-10s %s", name_style.render(code), dim_style.render(desc))
      end
      puts ""

      puts category_style.render("Mutation Patterns:")
      puts "  " + name_style.render("od, once") + " - Mutate once at a single target"
      puts "  " + name_style.render("nd, many") + " - Mutate multiple times with geometric probability decay (default)"
      puts "  " + name_style.render("bu, burst") + " - Mutate in localized burst clusters"
      puts ""

      puts category_style.render("Mutators (30 Arsenal Tools):")
      pool = MutatorPool.new
      pool.mutators.each do |m|
        puts sprintf("  %-8s %s", name_style.render(m.name), dim_style.render(m.description))
      end
      puts ""

      puts category_style.render("Selectors & Combinators:")
      selectors = [
        {"bytes", "ByteRange: static byte index range (e.g. 0...16)"},
        {"header", "Header: prefix bytes (or inverted)"},
        {"footer", "Footer: suffix bytes (or inverted)"},
        {"regex", "Regex: regular expression match with capture groups"},
        {"delims", "Delimiters: balanced pairs (), [], {}, <>, \"\", ''"},
        {"field", "DelimitedField: N-th column or token by delimiter"},
        {"chars", "CharacterClass: contiguous digits, hex, alpha, or printable"},
        {"stride", "Stride: periodic byte slices at regular intervals"},
        {"entropy", "Entropy: Shannon entropy slices (:high or :low)"},
        {"json_key", "JSONKeyPath: target specific JSON keys and values"},
        {"xml_tag", "XMLTag: target specific XML elements and inner text"},
        {"&, |, ~", "Combinators: logical intersection, union, and inversion"},
      ]
      selectors.each do |(code, desc)|
        puts sprintf("  %-10s %s", name_style.render(code), dim_style.render(desc))
      end
      puts ""
    end
  end
end
