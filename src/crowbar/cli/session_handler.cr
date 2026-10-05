require "opal"
require "json"
require "../session"
require "../rules/registry"
require "../patterns/base"
require "./diff"
require "./platform_io"

module Crowbar::CLI
  # Handles all stateful session subcommands:
  # next, reward, status, list, reset, setup, show, history
  class SessionHandler
    property in_io : IO
    property out_io : IO
    property err_io : IO
    property exit_handler : Proc(Int32, Nil)

    property selected_rule : String?
    property selected_pattern : String?
    property selected_mutations : String?
    property seed : UInt64?
    property show_diff : Bool
    property output_pattern : String?
    property json_output : Bool
    property template : String?
    property unique : Bool
    property checksums_capacity : Int32?
    property seek_offset : Int64?
    property input_encoding : String?
    property output_encoding : String?

    def initialize(
      @in_io : IO,
      @out_io : IO,
      @err_io : IO,
      @exit_handler : Proc(Int32, Nil),
      @selected_rule : String? = nil,
      @selected_pattern : String? = nil,
      @selected_mutations : String? = nil,
      @seed : UInt64? = nil,
      @show_diff : Bool = false,
      @output_pattern : String? = nil,
      @json_output : Bool = false,
      @template : String? = nil,
      @unique : Bool = false,
      @checksums_capacity : Int32? = nil,
      @seek_offset : Int64? = nil,
      @input_encoding : String? = nil,
      @output_encoding : String? = nil,
    )
    end

    private def puts(msg = "")
      @out_io.puts(msg)
    end

    private def err_puts(msg = "")
      @err_io.puts(msg)
    end

    private def do_exit(code : Int32 = 0)
      @exit_handler.call(code)
    end

    def handle(sub_args : Array(String))
      if sub_args.empty? || sub_args[0] == "-h" || sub_args[0] == "--help"
        print_session_help
        do_exit(0)
        return
      end

      # crowbar session list
      if sub_args[0] == "list"
        handle_session_list(sub_args.includes?("--json") || @json_output)
        return
      end

      # crowbar session setup <id> [options]
      if sub_args[0] == "setup"
        if sub_args.size < 2
          err_puts Opal.style.fg(:red).render("Error: Missing session ID. Usage: crowbar session setup <id> [options]")
          do_exit(1)
          return
        end
        session_id = sub_args[1]
        setup_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_setup(session_id, setup_flags)
        return
      end

      # crowbar session review <id> [options]
      if sub_args[0] == "review"
        if sub_args.size < 2
          err_puts Opal.style.fg(:red).render("Error: Missing session ID. Usage: crowbar session review <id> [options]")
          do_exit(1)
          return
        end
        session_id = sub_args[1]
        review_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_review(session_id, review_flags)
        return
      end

      # crowbar session replay <id> <iteration> [options]
      if sub_args[0] == "replay"
        if sub_args.size < 2
          err_puts Opal.style.fg(:red).render("Error: Missing session ID. Usage: crowbar session replay <id> <iteration> [options]")
          do_exit(1)
          return
        end
        session_id = sub_args[1]
        replay_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_replay(session_id, replay_flags)
        return
      end

      session_id = sub_args[0]
      if sub_args.size < 2
        err_puts Opal.style.fg(:red).render("Error: Missing action for session '#{session_id}'. Usage: crowbar session #{session_id} <action>")
        print_session_help
        do_exit(1)
        return
      end

      action = sub_args[1]
      case action
      when "next"
        next_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_next(session_id, next_flags)
      when "reward"
        reward_args = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_reward(session_id, reward_args)
      when "review"
        review_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_review(session_id, review_flags)
      when "replay"
        replay_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_replay(session_id, replay_flags)
      when "reset"
        handle_session_reset(session_id)
      when "status"
        use_json = sub_args.includes?("--json") || @json_output
        handle_session_status(session_id, use_json)
      when "show"
        target = sub_args.size > 2 ? sub_args[2] : nil
        handle_session_show(session_id, target)
      when "history"
        use_json = sub_args.includes?("--json") || @json_output
        limit = 20
        if idx = sub_args.index("--limit") || sub_args.index("-n")
          limit = sub_args[idx + 1]?.try(&.to_i?) || 20
        end
        handle_session_history(session_id, limit, use_json)
      when "setup"
        setup_flags = sub_args.size > 2 ? sub_args[2..] : [] of String
        handle_session_setup(session_id, setup_flags)
      else
        err_puts Opal.style.fg(:red).render("Unknown session action: '#{action}'")
        print_session_help
        do_exit(1)
      end
    end

    private def read_piped_stdin : Buffer?
      return nil unless PlatformIO.has_data?(@in_io)
      buf = Buffer.from_io(@in_io)
      buf.empty? ? nil : buf
    rescue
      nil
    end

    private def handle_session_next(session_id : String, sub_flags : Array(String) = [] of String)
      req_unique = @unique
      req_seek = @seek_offset
      req_seed = @seed
      req_template = @template
      req_in_encoding = @input_encoding
      req_out_encoding = @output_encoding
      out_pattern = @output_pattern
      diff_mode = @show_diff
      req_mutations : Array(String)? = @selected_mutations.try { |m| m.split(",") }
      req_capacity : Int32? = @checksums_capacity

      i = 0
      while i < sub_flags.size
        arg = sub_flags[i]
        case arg
        when "-s", "--seed"
          if i + 1 < sub_flags.size
            req_seed = sub_flags[i + 1].to_u64? || sub_flags[i + 1].hash.to_u64
            i += 2
          else
            i += 1
          end
        when "-t", "--template"
          if i + 1 < sub_flags.size
            req_template = sub_flags[i + 1]
            i += 2
          else
            i += 1
          end
        when "-u", "--unique"
          req_unique = true
          i += 1
        when "-S", "--seek"
          if i + 1 < sub_flags.size
            req_seek = sub_flags[i + 1].to_i64?
            i += 2
          else
            i += 1
          end
        when "-I", "--in-format", "--input-encoding", "--input-format"
          if i + 1 < sub_flags.size
            req_in_encoding = sub_flags[i + 1]
            i += 2
          else
            i += 1
          end
        when "-O", "--out-format", "--output-encoding", "--output-format"
          if i + 1 < sub_flags.size
            req_out_encoding = sub_flags[i + 1]
            i += 2
          else
            i += 1
          end
        when "-C", "--checksums"
          if i + 1 < sub_flags.size
            req_capacity = sub_flags[i + 1].to_i?
            i += 2
          else
            i += 1
          end
        when "-d", "--diff"
          diff_mode = true
          i += 1
        when "-o", "--output"
          if i + 1 < sub_flags.size
            out_pattern = sub_flags[i + 1]
            i += 2
          else
            i += 1
          end
        when "-m", "--mutations"
          if i + 1 < sub_flags.size
            req_mutations = sub_flags[i + 1].split(",")
            i += 2
          else
            i += 1
          end
        else
          i += 1
        end
      end

      piped_raw = read_piped_stdin
      existing_sess = Session.exists?(session_id) ? Session.load(session_id) : nil
      effective_in = req_in_encoding || existing_sess.try(&.input_encoding)
      piped = if piped_raw && effective_in
                Encoding.decode(piped_raw, effective_in)
              else
                piped_raw
              end

      session = if existing_sess
                  sess = existing_sess
                  if piped && piped != sess.baseline
                    sess.reset_with(piped, @selected_rule, @selected_pattern, @selected_mutations, @seed)
                    sess.save
                  end
                  sess
                else
                  if piped.nil?
                    err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
                    err_puts "Pipe initial data to start the session:"
                    err_puts "  echo 'sample' | crowbar session #{session_id} next"
                    do_exit(1)
                    return
                  end
                  Session.load_or_create(session_id, piped, @selected_rule, @selected_pattern, @selected_mutations, @seed)
                end

      if in_enc = req_in_encoding
        session.input_encoding = in_enc
      end
      if out_enc = req_out_encoding
        session.output_encoding = out_enc
      end
      if cap = req_capacity
        session.uniqueness_capacity = cap
      end
      if s = req_seed
        session.seed = s
      end
      if muts = req_mutations
        session.set_mutators(muts)
      end

      mutated = session.next_mutant(
        unique: req_unique ? true : nil,
        seek: req_seek,
        template_override: req_template
      )

      payload = if enc = req_out_encoding || session.output_encoding
                  Encoding.encode(mutated, enc).to_slice
                else
                  mutated.to_slice
                end

      if diff_mode
        HexDiff.render(session.baseline, mutated, @out_io)
      elsif pattern = out_pattern
        if pattern == "-"
          @out_io.write(payload)
        else
          filename = pattern.gsub("%n", session.iteration.to_s)
          File.write(filename, payload)
        end
      else
        @out_io.write(payload)
      end
    end

    private def handle_session_reward(session_id : String, sub_args : Array(String))
      val_str : String? = nil
      target_iter : Int32? = nil

      i = 0
      while i < sub_args.size
        arg = sub_args[i]
        case arg
        when "-i", "--iteration", "-n"
          if i + 1 < sub_args.size
            target_iter = sub_args[i + 1].to_i?
            i += 2
          else
            i += 1
          end
        else
          val_str ||= arg
          i += 1
        end
      end

      unless val_str
        err_puts Opal.style.fg(:red).render("Error: Missing reward value. Usage: crowbar session #{session_id} reward <value> [--iteration <N>]")
        err_puts "Example: crowbar session #{session_id} reward 0.5 -i 3"
        do_exit(1)
        return
      end

      reward_val = val_str.to_f64?
      unless reward_val
        err_puts Opal.style.fg(:red).render("Error: Invalid reward value '#{val_str}'. Must be a floating point number.")
        do_exit(1)
        return
      end

      session = Session.load(session_id)
      unless session
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        do_exit(1)
        return
      end

      if session.items.empty? && session.last_mutators.empty?
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' has not generated any items yet. Run 'next' first.")
        do_exit(1)
        return
      end

      begin
        session.reward(reward_val, target_iter)
        iter_desc = target_iter ? "iteration ##{target_iter}" : "session #{session_id}"
        puts Opal.style.fg(:green).render("Recorded reward #{reward_val} for #{iter_desc} (Bandit & Corpus updated)")
      rescue ex
        err_puts Opal.style.fg(:red).render("Error: #{ex.message}")
        do_exit(1)
      end
    end

    private def handle_session_review(session_id : String, sub_flags : Array(String))
      session = Session.load(session_id)
      unless session
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        do_exit(1)
        return
      end

      no_tui = sub_flags.includes?("--no-tui") || sub_flags.includes?("--headless") || sub_flags.includes?("--batch")
      use_json = sub_flags.includes?("--json") || @json_output
      is_tty = PlatformIO.tty?(@out_io)

      limit = 25
      if idx = sub_flags.index("--limit") || sub_flags.index("-n")
        limit = sub_flags[idx + 1]?.try(&.to_i?) || 25
      end

      if no_tui || use_json || !is_tty
        TUI::SummaryView.render(session, @out_io, limit: limit, json: use_json)
      else
        TUI::Reviewer.run(session)
      end
    end

    private def handle_session_replay(session_id : String, sub_flags : Array(String))
      if sub_flags.empty?
        err_puts Opal.style.fg(:red).render("Error: Missing iteration number to replay. Usage: crowbar session #{session_id} replay <iteration> [options]")
        do_exit(1)
        return
      end

      iter = sub_flags[0].to_i?
      unless iter
        err_puts Opal.style.fg(:red).render("Error: Invalid iteration number '#{sub_flags[0]}'. Must be an integer.")
        do_exit(1)
        return
      end

      session = Session.load(session_id)
      unless session
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        do_exit(1)
        return
      end

      item = session.get_item(iter)
      unless item
        err_puts Opal.style.fg(:red).render("Error: Iteration #{iter} not found in session '#{session_id}'.")
        do_exit(1)
        return
      end

      out_file : String? = @output_pattern
      show_diff = sub_flags.includes?("--diff") || sub_flags.includes?("-d") || @show_diff
      use_json = sub_flags.includes?("--json") || @json_output
      raw_output = sub_flags.includes?("--raw")

      if idx = sub_flags.index("-o") || sub_flags.index("--output")
        out_file = sub_flags[idx + 1]?
      end

      replayed_buf, steps = session.replay(iter)

      if f = out_file
        File.write(f, replayed_buf.to_slice)
        puts Opal.style.fg(:green).render("Replayed iteration #{iter} and wrote output to #{f} (#{replayed_buf.size} bytes).")
        return
      end

      if raw_output
        @out_io.write(replayed_buf.to_slice)
        return
      end

      if use_json
        payload = {
          "session_id" => session_id,
          "iteration"  => iter,
          "seed"       => item.seed.to_s,
          "seek"       => item.seek_offset,
          "size"       => replayed_buf.size,
          "mutators"   => item.mutators,
          "diff_bytes" => item.diff_count,
          "steps"      => steps.map do |s|
            {
              "index"       => s.index,
              "category"    => s.category.to_s.downcase,
              "name"        => s.name,
              "description" => s.description,
              "range"       => s.range_string,
              "diff_bytes"  => s.diff_bytes,
            }
          end,
        }
        @out_io.puts(payload.to_pretty_json)
        return
      end

      bold = Opal.style.bold
      cyan = Opal.style.bold.fg(:cyan)
      yellow = Opal.style.fg(:yellow)
      dim = Opal.style.fg(:bright_black)

      puts cyan.render("=== Replayed Iteration ##{iter} for Session '#{session_id}' ===")
      puts dim.render(sprintf("Seed: 0x%X | Seek: %d | Baseline: %d B -> Mutant: %d B (Diff: %d B)", item.seed, item.seek_offset, session.baseline.size, replayed_buf.size, item.diff_count))
      puts dim.render("Mutators: #{item.mutators.join(", ")}")
      puts dim.render("-" * 72)
      puts bold.render("Transformation Process Tree:")

      steps.each do |s|
        badge = s.category.to_badge
        delta = s.diff_bytes != 0 ? " (#{s.diff_string})" : ""
        puts sprintf("  %d. %-10s %-12s %s%s", s.index, badge, s.name, s.description, yellow.render(delta))
      end

      if show_diff
        puts ""
        HexDiff.render(session.baseline, replayed_buf, @out_io)
      end
    end

    private def handle_session_reset(session_id : String)
      if Session.exists?(session_id)
        Session.reset(session_id)
        puts Opal.style.fg(:green).render("Session '#{session_id}' has been reset.")
      else
        err_puts Opal.style.fg(:yellow).render("Session '#{session_id}' does not exist.")
      end
    end

    private def handle_session_show(session_id : String, target : String?)
      session = Session.load(session_id)
      unless session
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        do_exit(1)
        return
      end

      case target
      when "--baseline", "-b", "baseline"
        @out_io.write(session.baseline.to_slice)
      when "--mutant", "-m", "mutant", nil
        if m = session.last_mutant
          @out_io.write(m.to_slice)
        else
          err_puts Opal.style.fg(:yellow).render("Session '#{session_id}' has not generated any mutants yet.")
          do_exit(1)
        end
      else
        if iter = target.to_i?
          if buf = session.get_mutant(iter)
            @out_io.write(buf.to_slice)
          else
            err_puts Opal.style.fg(:red).render("Error: Could not retrieve mutant for iteration #{iter} in session '#{session_id}'.")
            do_exit(1)
          end
        else
          err_puts Opal.style.fg(:red).render("Unknown show target '#{target}'. Use '--baseline', '--mutant', or iteration number.")
          do_exit(1)
        end
      end
    end

    private def handle_session_history(session_id : String, limit : Int32, json : Bool)
      session = Session.load(session_id)
      unless session
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        do_exit(1)
        return
      end

      entries = session.history.last(limit)

      if json
        puts entries.to_pretty_json
        return
      end

      title_style = Opal.style.bold.fg(:cyan)
      header_style = Opal.style.bold.fg(:yellow)

      puts title_style.render("=== History for Session #{session_id} (last #{entries.size} events) ===")
      puts sprintf("%-6s | %-8s | %-8s | %s", header_style.render("Iter"), header_style.render("Action"), header_style.render("Reward"), header_style.render("Mutators Applied"))
      puts "-" * 60

      entries.each do |e|
        rew_str = e.value ? sprintf("%+.2f", e.value.not_nil!) : "-"
        muts_str = e.mutators.empty? ? "-" : e.mutators.join(", ")
        puts sprintf("%-6d | %-8s | %-8s | %s", e.iteration, e.action, rew_str, muts_str)
      end
    end

    private def handle_session_status(session_id : String, json : Bool)
      session = Session.load(session_id)
      unless session
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        do_exit(1)
        return
      end

      if json
        data = {
          "id"                 => session.id,
          "created_at"         => session.created_at,
          "updated_at"         => session.updated_at,
          "iteration"          => session.iteration,
          "baseline_size"      => session.baseline.size,
          "rules"              => session.active_rules.empty? ? (session.rule_name ? [session.rule_name.not_nil!] : [] of String) : session.active_rules,
          "pattern"            => session.pattern_name || "many",
          "selected_mutations" => session.selected_mutations,
          "last_reward"        => session.last_reward,
          "last_mutators"      => session.last_mutators,
          "total_pulls"        => session.total_pulls,
          "corpus_size"        => session.corpus_items.size,
          "arms"               => session.arms.map do |k, v|
            {
              "name"    => k,
              "pulls"   => v.pulls,
              "rewards" => v.rewards,
              "average" => v.pulls > 0 ? (v.rewards / v.pulls) : 0.0,
            }
          end,
          "scopes" => session.scopes.map do |sc|
            {
              "name"          => sc.name,
              "selector_type" => sc.selector_type,
              "params"        => sc.params,
              "weight"        => sc.weight,
            }
          end,
          "template"            => session.template,
          "unique_enabled"      => session.unique_enabled,
          "uniqueness_capacity" => session.uniqueness_capacity,
          "seen_hashes_count"   => session.seen_hashes.size,
          "seek_offset"         => session.seek_offset,
          "input_encoding"      => session.input_encoding,
          "output_encoding"     => session.output_encoding,
        }
        puts data.to_pretty_json
        return
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
      tmpl_str = session.template ? session.template.not_nil! : "none"
      puts "#{label_style.render("Template:")}  #{tmpl_str}"
      uniq_str = session.unique_enabled ? "enabled (capacity: #{session.uniqueness_capacity}, seen: #{session.seen_hashes.size})" : "disabled"
      puts "#{label_style.render("Unique Filter:")} #{uniq_str}"
      if session.seek_offset != 0
        puts "#{label_style.render("Seek Offset:")}   #{session.seek_offset}"
      end
      if in_enc = session.input_encoding
        puts "#{label_style.render("In Format:")}   #{in_enc}"
      end
      if out_enc = session.output_encoding
        puts "#{label_style.render("Out Format:")}  #{out_enc}"
      end
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

    private def handle_session_list(json : Bool)
      sessions = Session.list
      if json
        data = sessions.map do |id|
          sess = Session.load(id)
          {
            "id"         => id,
            "iteration"  => sess ? sess.iteration : 0,
            "baseline"   => sess ? sess.baseline.size : 0,
            "rules"      => sess ? (sess.active_rules.empty? ? (sess.rule_name ? [sess.rule_name.not_nil!] : [] of String) : sess.active_rules) : [] of String,
            "updated_at" => sess ? sess.updated_at.to_s : "",
          }
        end
        puts data.to_pretty_json
        return
      end

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

    private def handle_session_setup(session_id : String, sub_args : Array(String))
      session = Session.load(session_id)
      unless session
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' does not exist.")
        err_puts "Create it first by piping baseline data:"
        err_puts "  cat sample.mp3 | crowbar session #{session_id} next"
        do_exit(1)
        return
      end

      if sub_args.empty? && @selected_rule.nil? && @selected_pattern.nil? && @selected_mutations.nil? && @template.nil? && !@unique && @seek_offset.nil? && @checksums_capacity.nil? && @input_encoding.nil? && @output_encoding.nil?
        display_session_setup_status(session)
        return
      end

      i = 0
      modified = false

      if in_enc = @input_encoding
        session.input_encoding = in_enc
        puts Opal.style.fg(:green).render("Set input encoding to '#{in_enc}' for session #{session_id}")
        modified = true
      end

      if out_enc = @output_encoding
        session.output_encoding = out_enc
        puts Opal.style.fg(:green).render("Set output encoding to '#{out_enc}' for session #{session_id}")
        modified = true
      end

      if r = @selected_rule
        session.add_rule(r)
        puts Opal.style.fg(:green).render("Added rule '#{r}' to session #{session_id}")
        modified = true
      end

      if m = @selected_mutations
        mut_names = m.split(",").map(&.strip)
        session.set_mutators(mut_names)
        puts Opal.style.fg(:green).render("Set mutator pool to [#{mut_names.join(", ")}] for session #{session_id}")
        modified = true
      end

      if pat = @selected_pattern
        session.pattern_name = pat
        puts Opal.style.fg(:green).render("Set pattern to #{pat} for session #{session_id}")
        modified = true
      end

      if t = @template
        session.set_template(t)
        puts Opal.style.fg(:green).render("Set template to '#{t}' for session #{session_id}")
        modified = true
      end

      if @unique
        session.set_unique(true)
        puts Opal.style.fg(:green).render("Enabled uniqueness deduplication filter for session #{session_id}")
        modified = true
      end

      if cap = @checksums_capacity
        session.uniqueness_capacity = cap
        puts Opal.style.fg(:green).render("Set uniqueness checksums capacity to #{cap} for session #{session_id}")
        modified = true
      end

      if s = @seek_offset
        session.set_seek(s)
        puts Opal.style.fg(:green).render("Set seek offset to #{s} for session #{session_id}")
        modified = true
      end

      scope_name : String? = nil
      selector_type : String? = nil
      scope_params = Hash(String, String).new
      scope_weight = 1.0

      while i < sub_args.size
        arg = sub_args[i]
        case arg
        when "--add-rule"
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
          puts Opal.style.fg(:yellow).render("Cleared all active rules for session #{session_id}")
          modified = true
          i += 1
        when "--auto-rule", "--auto-detect"
          if detected = session.auto_detect_rule
            puts Opal.style.fg(:green).render("Auto-detected and configured rule '#{detected}' for session #{session_id}")
            modified = true
          else
            err_puts Opal.style.fg(:yellow).render("Could not auto-detect format from session #{session_id} baseline data.")
          end
          i += 1
        when "--add-mutator"
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
        when "--template", "-t"
          if i + 1 < sub_args.size
            t_spec = sub_args[i + 1]
            session.set_template(t_spec)
            puts Opal.style.fg(:green).render("Set template to '#{t_spec}' for session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--remove-template", "--clear-template"
          session.set_template(nil)
          puts Opal.style.fg(:yellow).render("Removed template from session #{session_id}")
          modified = true
          i += 1
        when "--unique", "-u"
          session.set_unique(true)
          puts Opal.style.fg(:green).render("Enabled uniqueness deduplication filter for session #{session_id}")
          modified = true
          i += 1
        when "--no-unique", "--disable-unique"
          session.set_unique(false)
          puts Opal.style.fg(:yellow).render("Disabled uniqueness deduplication filter for session #{session_id}")
          modified = true
          i += 1
        when "--checksums", "-C"
          if i + 1 < sub_args.size
            c_val = sub_args[i + 1].to_i? || 10_000
            session.uniqueness_capacity = c_val
            puts Opal.style.fg(:green).render("Set uniqueness checksums capacity to #{c_val} for session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--seek", "-S"
          if i + 1 < sub_args.size
            s_val = sub_args[i + 1].to_i64? || 0_i64
            session.set_seek(s_val)
            puts Opal.style.fg(:green).render("Set seek offset to #{s_val} for session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--clear-checksums", "--clear-seen"
          session.clear_seen_hashes
          puts Opal.style.fg(:yellow).render("Cleared uniqueness seen hashes for session #{session_id}")
          modified = true
          i += 1
        when "--in-format", "--input-encoding", "-I", "--input-format"
          if i + 1 < sub_args.size
            fmt = sub_args[i + 1]
            session.input_encoding = fmt
            puts Opal.style.fg(:green).render("Set input encoding to '#{fmt}' for session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--out-format", "--output-encoding", "-O", "--output-format"
          if i + 1 < sub_args.size
            fmt = sub_args[i + 1]
            session.output_encoding = fmt
            puts Opal.style.fg(:green).render("Set output encoding to '#{fmt}' for session #{session_id}")
            modified = true
            i += 2
          else
            i += 1
          end
        when "--clear-encodings", "--reset-encodings"
          session.input_encoding = nil
          session.output_encoding = nil
          puts Opal.style.fg(:yellow).render("Cleared input/output encodings for session #{session_id}")
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
        when "--selector", "-s"
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
          print_setup_help
          do_exit(0)
          return
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
      puts "#{label_style.render("Mutator Filter:")}  #{session.selected_mutations || "all mutators active"}"
      tmpl_str = session.template ? session.template.not_nil! : "none"
      puts "#{label_style.render("Template:")}        #{tmpl_str}"
      uniq_str = session.unique_enabled ? "enabled (capacity: #{session.uniqueness_capacity}, seen: #{session.seen_hashes.size})" : "disabled"
      puts "#{label_style.render("Unique Filter:")}   #{uniq_str}"
      if session.seek_offset != 0
        puts "#{label_style.render("Seek Offset:")}     #{session.seek_offset}"
      end
      if in_enc = session.input_encoding
        puts "#{label_style.render("In Format:")}       #{in_enc}"
      end
      if out_enc = session.output_encoding
        puts "#{label_style.render("Out Format:")}      #{out_enc}"
      end
      if session.scopes.empty?
        puts "#{label_style.render("Scopes:")}          None (whole buffer mutation)"
      else
        puts "#{label_style.render("Active Scopes:")}"
        session.scopes.each do |sc|
          params_desc = sc.params.empty? ? "" : " params: #{sc.params.inspect}"
          puts "  - #{sc.name}: #{sc.selector_type} (weight: #{sc.weight})#{params_desc}"
        end
      end
    end

    private def print_session_help
      banner = Opal.style.bold.fg(:cyan).render("Crowbar Session System - Stateful Fuzzing & Feedback")
      puts banner
      puts "\nUsage: crowbar session <id> <action> [options]"
      puts ""
      puts "Actions:"
      puts "  next [flags]      Generate the next mutated item from session baseline"
      puts "                    Flags: -t/--template, -u/--unique, -S/--seek, -d/--diff, -o/--output"
      puts "  reward <val>      Provide feedback (-1.0 to 1.0) on mutant (latest or -i/--iteration <N>)"
      puts "  review [flags]    Interactive TUI session reviewer, hex diff & breakdown (--no-tui, --json)"
      puts "  replay <#> [opts] Deterministically replay an iteration and inspect transformation breakdown"
      puts "  setup [options]   Configure active rules, mutators, templates, uniqueness, scopes"
      puts "  show [opts]       Print baseline, latest mutant, or iteration N (--baseline, --mutant, <#)"
      puts "  history [opts]    Display event history timeline (--limit N, --json)"
      puts "  reset             Reset and delete the session"
      puts "  status [--json]   Display session statistics, iteration count & bandit weights"
      puts "  list [--json]     List all active sessions"
      puts ""
      puts "Workflow Examples:"
      puts "  1. Initialize with input:  \"POST / HTTP/1.1\\r\\n\\r\\n\" | crowbar session 1 next"
      puts "  2. Review in TUI:          crowbar session 1 review"
      puts "  3. Replay iteration #3:    crowbar session 1 replay 3 --diff"
      puts "  4. Reward iteration #3:    crowbar session 1 reward 1.0 -i 3"
      puts "  5. Templated generation:   crowbar session 1 next -t \"PREFIX %f SUFFIX\""
      puts "  6. Unique deduplication:   crowbar session 1 next --unique"
      puts "  7. Show past mutant:       crowbar session 1 show 3"
      puts "  8. View event history:     crowbar session 1 history --limit 10"
      puts "  9. Configure session:      crowbar session 1 setup --add-rule mp3 --add-mutator sec --unique"
      puts " 10. Reset session:          crowbar session 1 reset"
    end

    private def print_setup_help
      banner = Opal.style.bold.fg(:cyan).render("Crowbar Session Setup - Configure Rules, Selectors & Scopes")
      puts banner
      puts "\nUsage: crowbar session <id> setup [options]"
      puts ""
      puts "Options:"
      puts "  --add-rule <name>         Add a structure rule (e.g. mp3, wav, png, bmp, wad, pdf, http)"
      puts "  --remove-rule <name>      Remove an active rule"
      puts "  --clear-rules             Clear all active rules"
      puts "  --auto-rule               Auto-detect rule from session baseline payload"
      puts "  --add-mutator <m>         Add mutator to pool (e.g. sec, fuse, splice, ab, num, bf)"
      puts "  --remove-mutator <m>      Remove mutator from pool"
      puts "  --set-mutators <m1,m2>    Restrict mutator pool to comma-separated list"
      puts "  --reset-mutators          Restore default full mutator pool"
      puts "  --template, -t <spec>     Set output wrapper template ('%f' or '{{data}}' placeholder)"
      puts "  --remove-template         Clear output template"
      puts "  --unique, -u              Enable deduplication uniqueness filter"
      puts "  --no-unique               Disable deduplication uniqueness filter"
      puts "  --checksums, -C <N>       Set uniqueness ring buffer capacity (default: 10,000)"
      puts "  --seek, -S <offset>       Set PRNG fast-forward seek offset"
      puts "  --clear-checksums         Clear uniqueness seen hashes ring buffer"
      puts "  --pattern, -p <pattern>   Set execution pattern (many, burst, once)"
      puts "  --add-scope <name>        Add named targeting scope"
      puts "  --selector, -s <type>     Selector type (range, header, footer, field, chars, stride, entropy, regex)"
      puts "  --params <k:v,...>        Selector parameters"
      puts "  --weight, -w <num>        Weight multiplier for scope (default: 1.0)"
      puts "  --remove-scope <name>     Remove named scope"
      puts "  --clear-scopes            Clear all configured scopes"
    end
  end
end
