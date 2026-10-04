require "option_parser"
require "opal"
require "../../crowbar"
require "./diff"

{% if flag?(:windows) %}
  lib LibC
    fun PeekNamedPipe(
      hNamedPipe : HANDLE,
      lpBuffer : Void*,
      nBufferSize : DWORD,
      lpBytesRead : DWORD*,
      lpTotalBytesAvail : DWORD*,
      lpBytesLeftThisMessage : DWORD*,
    ) : BOOL
  end
{% end %}

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
      # Handle session subcommands if present
      if args.includes?("session")
        remaining = extract_flags(args)
        handle_session_command(remaining)
        return
      end

      parser = OptionParser.new do |opts|
        opts.banner = Opal.style.bold.fg(:cyan).render("Crowbar #{Crowbar.version} - Data Transformation & Fuzzing Engine") +
                      "\nUsage: crowbar [options] [sample-files...]" +
                      "\n       crowbar session <id> next" +
                      "\n       crowbar session <id> reward <value>" +
                      "\n       crowbar session <id> reset"

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

        opts.on("-r RULE", "--rule RULE", "Structure-preserving rule: json, yaml, http, dns, csv, xml, url, tlv, base64, varint, ftp, sql") do |r|
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
        when "ftp"           then engine.add_rule(Rules::FTPRule.new)
        when "sql"           then engine.add_rule(Rules::SQLRule.new)
        when "png"           then engine.add_rule(Rules::PNGRule.new)
        when "bmp"           then engine.add_rule(Rules::BMPRule.new)
        when "wav"           then engine.add_rule(Rules::WAVRule.new)
        when "mp3"           then engine.add_rule(Rules::MP3Rule.new)
        when "wad"           then engine.add_rule(Rules::WADRule.new)
        when "pdf"           then engine.add_rule(Rules::PDFRule.new)
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

      puts category_style.render("Structure-Preserving Rules (18 Formats):")
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
        {"ftp", "RFC 959 FTP command and response streams with CRLF framing"},
        {"sql", "Structure-preserving SQL statement with mutated literals & operators"},
        {"png", "Portable Network Graphics with automatic chunk framing & CRC32 recalculation"},
        {"bmp", "Windows Bitmap (BMP) with header dimensions, compression & pixel rasters"},
        {"wav", "RIFF/WAVE audio streams with fmt parameters, channels & PCM samples"},
        {"mp3", "MPEG Layer III audio with ID3v2 tags and synchronized frame headers"},
        {"wad", "Doom WAD directory tables, lump metadata, and THINGS/LINEDEFS payloads"},
        {"pdf", "Portable Document Format (PDF) objects, dictionaries, streams & xrefs"},
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

      pool = MutatorPool.new
      puts category_style.render("Mutators (#{pool.mutators.size} Arsenal Tools):")
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

    private def extract_flags(args : Array(String)) : Array(String)
      remaining = [] of String
      i = 0
      while i < args.size
        arg = args[i]
        case arg
        when "-r", "--rule"
          if i + 1 < args.size
            @selected_rule = args[i + 1]
            i += 2
            next
          end
        when "-s", "--seed"
          if i + 1 < args.size
            @seed = args[i + 1].to_u64? || args[i + 1].hash.to_u64
            i += 2
            next
          end
        when "-p", "--patterns"
          if i + 1 < args.size
            @selected_pattern = args[i + 1]
            i += 2
            next
          end
        when "-m", "--mutations"
          if i + 1 < args.size
            @selected_mutations = args[i + 1]
            i += 2
            next
          end
        when "-d", "--diff"
          @show_diff = true
          i += 1
          next
        when "-o", "--output"
          if i + 1 < args.size
            @output_pattern = args[i + 1]
            i += 2
            next
          end
        else
          remaining << arg
          i += 1
        end
      end
      remaining
    end

    private def stdin_has_data? : Bool
      return false if STDIN.tty?
      {% if flag?(:windows) %}
        h = LibC.GetStdHandle(LibC::STD_INPUT_HANDLE)
        if LibC.PeekNamedPipe(h, nil, 0, nil, out avail, nil) != 0
          return avail > 0
        end
        false
      {% else %}
        selected = IO.select([STDIN], timeout: 0.seconds)
        !selected.nil? && !selected.empty?
      {% end %}
    rescue
      false
    end

    private def read_piped_stdin : Buffer?
      return nil unless stdin_has_data?
      buf = Buffer.from_io(STDIN)
      buf.empty? ? nil : buf
    rescue
      nil
    end

    private def handle_session_command(args : Array(String))
      session_idx = args.index("session")
      return unless session_idx

      sub_args = args[(session_idx + 1)..]
      if sub_args.empty? || sub_args[0] == "-h" || sub_args[0] == "--help"
        print_session_help
        exit 0
      end

      # crowbar session list
      if sub_args[0] == "list"
        handle_session_list
        return
      end

      # Support crowbar session setup <id> [options]
      if sub_args[0] == "setup"
        if sub_args.size < 2
          STDERR.puts Opal.style.fg(:red).render("Error: Missing session ID. Usage: crowbar session setup <id> [options]")
          exit 1
        end
        session_id = sub_args[1]
        setup_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_setup(session_id, setup_flags)
        return
      end

      session_id = sub_args[0]
      action = sub_args.size > 1 ? sub_args[1].downcase : "next"

      case action
      when "next"
        handle_session_next(session_id)
      when "reward"
        val_str = sub_args.size > 2 ? sub_args[2] : nil
        handle_session_reward(session_id, val_str)
      when "reset"
        handle_session_reset(session_id)
      when "status", "info"
        handle_session_status(session_id)
      when "setup"
        setup_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_setup(session_id, setup_flags)
      else
        STDERR.puts Opal.style.fg(:red).render("Unknown session action: '#{action}'")
        print_session_help
        exit 1
      end
    end

    private def handle_session_setup(session_id : String, sub_args : Array(String))
      session = Session.load(session_id)
      unless session
        STDERR.puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        STDERR.puts "Create it first by piping baseline data:"
        STDERR.puts "  cat sample.mp3 | crowbar session #{session_id} next"
        exit 1
      end

      if sub_args.empty?
        display_session_setup_status(session)
        return
      end

      i = 0
      modified = false

      scope_name : String? = nil
      selector_type : String? = nil
      scope_params = Hash(String, String).new
      scope_weight = 1.0

      while i < sub_args.size
        arg = sub_args[i]
        case arg
        when "--add-rule", "-r"
          if i + 1 < sub_args.size
            r = sub_args[i + 1]
            session.add_rule(r)
            puts Opal.style.fg(:green).render("Added rule '#{r}' to session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--remove-rule"
          if i + 1 < sub_args.size
            r = sub_args[i + 1]
            session.remove_rule(r)
            puts Opal.style.fg(:yellow).render("Removed rule '#{r}' from session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--clear-rules"
          session.clear_rules
          puts Opal.style.fg(:yellow).render("Cleared all rules for session #{session_id}")
          modified = true
          i += 1
        when "--auto-rule", "--auto-detect"
          if detected = session.auto_detect_rule
            puts Opal.style.fg(:green).render("Auto-detected and applied rule '#{detected}' to session #{session_id}")
            modified = true
          else
            puts Opal.style.fg(:yellow).render("Could not auto-detect format from baseline for session #{session_id}")
          end
          i += 1
        when "--add-mutator", "-m"
          if i + 1 < sub_args.size
            m = sub_args[i + 1]
            session.add_mutator(m)
            puts Opal.style.fg(:green).render("Added mutator '#{m}' to session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--remove-mutator"
          if i + 1 < sub_args.size
            m = sub_args[i + 1]
            session.remove_mutator(m)
            puts Opal.style.fg(:yellow).render("Removed mutator '#{m}' from session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--set-mutators"
          if i + 1 < sub_args.size
            list = sub_args[i + 1].split(",")
            session.set_mutators(list)
            puts Opal.style.fg(:green).render("Set mutator pool to [#{list.join(", ")}] for session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--reset-mutators"
          session.reset_mutators
          puts Opal.style.fg(:yellow).render("Reset mutator pool to default (all mutators) for session #{session_id}")
          modified = true
          i += 1
        when "--pattern", "-p"
          if i + 1 < sub_args.size
            p = sub_args[i + 1]
            session.set_pattern(p)
            puts Opal.style.fg(:green).render("Set pattern to '#{p}' for session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--add-scope"
          if i + 1 < sub_args.size
            scope_name = sub_args[i + 1]
            i += 2
          else
            i += 1
          end
        when "--selector"
          if i + 1 < sub_args.size
            selector_type = sub_args[i + 1]
            i += 2
          else
            i += 1
          end
        when "--params"
          if i + 1 < sub_args.size
            pairs = sub_args[i + 1].split(",")
            pairs.each do |pair|
              if pair.includes?(":")
                k, v = pair.split(":", 2)
                scope_params[k.strip] = v.strip
              end
            end
            i += 2
          else
            i += 1
          end
        when "--weight", "-w"
          if i + 1 < sub_args.size
            scope_weight = sub_args[i + 1].to_f64? || 1.0
            i += 2
          else
            i += 1
          end
        when "--remove-scope"
          if i + 1 < sub_args.size
            s_name = sub_args[i + 1]
            session.remove_scope(s_name)
            puts Opal.style.fg(:yellow).render("Removed scope '#{s_name}' from session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--clear-scopes"
          session.clear_scopes
          puts Opal.style.fg(:yellow).render("Cleared all scopes from session #{session_id}")
          modified = true
          i += 1
        when "-h", "--help"
          print_session_setup_help(session_id)
          exit 0
        else
          i += 1
        end
      end

      if scope_name
        sel_type = selector_type || "range"
        session.add_scope(scope_name, sel_type, scope_params, scope_weight)
        params_desc = scope_params.empty? ? "" : " with params #{scope_params.inspect}"
        puts Opal.style.fg(:green).render("Configured scope '#{scope_name}' (#{sel_type}#{params_desc}, weight: #{scope_weight}) for session #{session_id}")
        modified = true
      end

      if modified
        session.save
      else
        display_session_setup_status(session)
      end
    end

    private def display_session_setup_status(session : Session)
      title_style = Opal.style.bold.fg(:cyan)
      label_style = Opal.style.bold.fg(:yellow)

      puts title_style.render("=== Session #{session.id} Configuration ===")
      rules_str = session.active_rules.empty? ? (session.rule_name || "none") : session.active_rules.join(", ")
      puts "#{label_style.render("Active Rules:")}    #{rules_str}"
      puts "#{label_style.render("Pattern:")}         #{session.pattern_name || "many (default)"}"
      puts "#{label_style.render("Mutator Pool:")}    #{session.selected_mutations || "all mutators active"}"
      if session.scopes.empty?
        puts "#{label_style.render("Scopes:")}          none (full buffer)"
      else
        puts "#{label_style.render("Scopes:")}          #{session.scopes.size} configured"
        session.scopes.each do |sc|
          params_str = sc.params.empty? ? "" : " (#{sc.params.map { |k, v| "#{k}: #{v}" }.join(", ")})"
          puts "  - #{sc.name}: #{sc.selector_type}#{params_str} [weight: #{sc.weight}]"
        end
      end
      puts ""
      puts "Use 'crowbar session #{session.id} setup --help' for setup options."
    end

    private def print_session_setup_help(session_id : String)
      banner = Opal.style.bold.fg(:cyan).render("Crowbar Session Setup - Configure Rules, Mutators, and Scopes")
      puts banner
      puts "\nUsage: crowbar session #{session_id} setup [options]"
      puts ""
      puts "Rule Management:"
      puts "  --add-rule <name>, -r <name>    Add a structure-preserving rule (e.g. mp3, png, wav, http)"
      puts "  --remove-rule <name>            Remove a rule from the session"
      puts "  --clear-rules                   Remove all rules from the session"
      puts "  --auto-rule, --auto-detect      Auto-detect format from session baseline and attach rule"
      puts ""
      puts "Mutator Pool Management:"
      puts "  --add-mutator <name>, -m <name> Add a mutator to active pool (e.g. num, bf, wd)"
      puts "  --remove-mutator <name>         Remove a mutator from active pool"
      puts "  --set-mutators <m1,m2,...>      Set exact active mutator pool"
      puts "  --reset-mutators                Reset mutator pool to default (all mutators)"
      puts ""
      puts "Pattern Selection:"
      puts "  --pattern <pat>, -p <pat>       Set mutation pattern (once, many, burst)"
      puts ""
      puts "Targeted Scope Management:"
      puts "  --add-scope <name>              Define or update a scoped target region"
      puts "  --selector <type>               Selector type: range, header, footer, delimited, chars, stride, entropy, regex"
      puts "  --params <k:v,...>              Parameters (e.g. start:0,end:10 or length:16 or delimiter:,)"
      puts "  --weight <float>, -w <float>    Scope selection weight (default 1.0)"
      puts "  --remove-scope <name>           Remove a configured scope"
      puts "  --clear-scopes                  Remove all configured scopes"
      puts ""
      puts "Examples:"
      puts "  crowbar session #{session_id} setup --add-rule mp3"
      puts "  crowbar session #{session_id} setup --set-mutators num,bf,wd -p burst"
      puts "  crowbar session #{session_id} setup --add-scope body --selector header --params length:32"
      puts "  crowbar session #{session_id} setup --auto-rule"
    end

    private def handle_session_next(session_id : String)
      piped = read_piped_stdin

      session = if Session.exists?(session_id)
                  sess = Session.load(session_id).not_nil!
                  if piped && piped != sess.baseline
                    # Auto-reset session on new input text
                    sess.reset_with(piped, @selected_rule, @selected_pattern, @selected_mutations, @seed)
                    sess.save
                  elsif @selected_rule || @selected_pattern || @selected_mutations
                    sess.rule_name = @selected_rule if @selected_rule
                    sess.pattern_name = @selected_pattern if @selected_pattern
                    sess.selected_mutations = @selected_mutations if @selected_mutations
                  end
                  sess
                else
                  if piped.nil?
                    STDERR.puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
                    STDERR.puts "Pipe initial data to start the session:"
                    STDERR.puts "  echo 'sample' | crowbar session #{session_id} next"
                    exit 1
                  end
                  Session.load_or_create(session_id, piped, @selected_rule, @selected_pattern, @selected_mutations, @seed)
                end

      mutated = session.next_mutant

      if @show_diff
        HexDiff.render(session.baseline, mutated)
      elsif pattern = @output_pattern
        write_output(pattern, mutated, session.iteration)
      else
        STDOUT.write(mutated.to_slice)
      end
    end

    private def handle_session_reward(session_id : String, val_str : String?)
      unless val_str
        STDERR.puts Opal.style.fg(:red).render("Error: Missing reward value. Usage: crowbar session #{session_id} reward <value>")
        STDERR.puts "Example: crowbar session #{session_id} reward 0.5"
        exit 1
      end

      reward_val = val_str.to_f64?
      unless reward_val
        STDERR.puts Opal.style.fg(:red).render("Error: Invalid reward value '#{val_str}'. Must be a floating point number.")
        exit 1
      end

      session = Session.load(session_id)
      unless session
        STDERR.puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        exit 1
      end

      if session.last_mutators.empty?
        STDERR.puts Opal.style.fg(:red).render("Error: Session '#{session_id}' has not generated any items yet. Run 'crowbar session #{session_id} next' first.")
        exit 1
      end

      session.reward(reward_val)
      puts Opal.style.fg(:green).render("Session #{session_id}: Recorded reward #{reward_val} for mutators [#{session.last_mutators.join(", ")}] (Iteration #{session.iteration})")
    end

    private def handle_session_reset(session_id : String)
      if Session.reset(session_id)
        puts Opal.style.fg(:green).render("Session '#{session_id}' has been reset.")
      else
        puts Opal.style.fg(:yellow).render("Session '#{session_id}' does not exist (nothing to reset).")
      end
    end

    private def handle_session_status(session_id : String)
      session = Session.load(session_id)
      unless session
        STDERR.puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        exit 1
      end

      title_style = Opal.style.bold.fg(:cyan)
      label_style = Opal.style.bold.fg(:yellow)

      puts title_style.render("=== Crowbar Session #{session.id} ===")
      puts "#{label_style.render("Created:")}   #{session.created_at}"
      puts "#{label_style.render("Updated:")}   #{session.updated_at}"
      puts "#{label_style.render("Iteration:")} #{session.iteration}"
      puts "#{label_style.render("Baseline:")}  #{session.baseline.size} B"
      rules_str = session.active_rules.empty? ? (session.rule_name || "none") : session.active_rules.join(", ")
      puts "#{label_style.render("Rules:")}     #{rules_str}"
      puts "#{label_style.render("Pattern:")}   #{session.pattern_name || "many (default)"}"
      puts "#{label_style.render("Mutators:")}  #{session.selected_mutations || "all mutators active"}"
      if !session.scopes.empty?
        puts "#{label_style.render("Scopes:")}    #{session.scopes.size} configured"
        session.scopes.each do |sc|
          params_str = sc.params.empty? ? "" : " (#{sc.params.map { |k, v| "#{k}: #{v}" }.join(", ")})"
          puts "  - #{sc.name}: #{sc.selector_type}#{params_str} [weight: #{sc.weight}]"
        end
      end
      if r = session.last_reward
        puts "#{label_style.render("Last Reward:")} #{r}"
      end
      if !session.last_mutators.empty?
        puts "#{label_style.render("Last Mutators:")} #{session.last_mutators.join(", ")}"
      end
      puts "#{label_style.render("Corpus Size:")} #{session.corpus_items.size} candidates"
      puts "#{label_style.render("Bandit Pulls:")} #{session.total_pulls} total pulls across #{session.arms.size} arms"
      if !session.arms.empty?
        puts ""
        puts label_style.render("Top Mutators by Cumulative Reward:")
        session.arms.to_a.sort_by { |_, a| -a.rewards }.first(5).each do |name, arm|
          avg = arm.pulls > 0 ? (arm.rewards / arm.pulls) : 0.0
          puts sprintf("  %-10s pulls: %-4d reward: %+.2f (avg: %+.2f)", name, arm.pulls, arm.rewards, avg)
        end
      end
    end

    private def handle_session_list
      sessions = Session.list
      if sessions.empty?
        puts "No active sessions found."
      else
        puts Opal.style.bold.fg(:cyan).render("=== Active Crowbar Sessions ===")
        sessions.each do |id|
          sess = Session.load(id)
          iter = sess ? sess.iteration : 0
          base_size = sess ? sess.baseline.size : 0
          rule = sess ? (sess.active_rules.empty? ? (sess.rule_name || "none") : sess.active_rules.join(", ")) : "none"
          puts sprintf("  %-10s | Iteration: %-4d | Baseline: %-5d B | Rule: %s", id, iter, base_size, rule)
        end
      end
    end

    private def print_session_help
      banner = Opal.style.bold.fg(:cyan).render("Crowbar Session System - Stateful Fuzzing & Feedback")
      puts banner
      puts "\nUsage: crowbar session <id> <action> [options]"
      puts ""
      puts "Actions:"
      puts "  next              Generate the next mutated item from session baseline"
      puts "  reward <val>      Provide feedback (-1.0 to 1.0) on the last generated mutant"
      puts "  setup [options]   Configure active rules, mutator pools, patterns, and scopes"
      puts "  reset             Reset and delete the session"
      puts "  status            Display session statistics, iteration count & bandit weights"
      puts "  list              List all active sessions"
      puts ""
      puts "Workflow Examples:"
      puts "  1. Initialize with input:  \"POST / HTTP/1.1\\r\\n\\r\\n\" | crowbar session 1 next"
      puts "  2. Reward feedback:        crowbar session 1 reward 0.5   (or -0.5)"
      puts "  3. Generate next:          crowbar session 1 next > out.txt"
      puts "  4. Configure session:      crowbar session 1 setup --add-rule mp3 --set-mutators num,bf"
      puts "  5. Reset session:          crowbar session 1 reset"
      puts "  6. Reset via new input:    \"NEW INPUT\" | crowbar session 1 next"
    end
  end
end
