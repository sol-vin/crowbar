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
        handle_session_next(session_id)
      when "reward"
        reward_val = sub_args.size > 2 ? sub_args[2] : nil
        handle_session_reward(session_id, reward_val)
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

    private def handle_session_next(session_id : String)
      piped = read_piped_stdin
      session = if Session.exists?(session_id)
                  sess = Session.load(session_id).not_nil!
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

      mutated = session.next_mutant

      if @show_diff
        HexDiff.render(session.baseline, mutated, @out_io)
      elsif pattern = @output_pattern
        if pattern == "-"
          @out_io.write(mutated.to_slice)
        else
          filename = pattern.gsub("%n", session.iteration.to_s)
          File.write(filename, mutated.to_slice)
        end
      else
        @out_io.write(mutated.to_slice)
      end
    end

    private def handle_session_reward(session_id : String, val_str : String?)
      unless val_str
        err_puts Opal.style.fg(:red).render("Error: Missing reward value. Usage: crowbar session #{session_id} reward <value>")
        err_puts "Example: crowbar session #{session_id} reward 0.5"
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

      if session.last_mutators.empty?
        err_puts Opal.style.fg(:red).render("Error: Session '#{session_id}' has not generated any items yet. Run 'crowbar session #{session_id} next' first.")
        do_exit(1)
        return
      end

      session.reward(reward_val)
      puts Opal.style.fg(:green).render("Recorded reward #{reward_val} for session #{session_id} (mutators: #{session.last_mutators.join(", ")})")
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
        err_puts Opal.style.fg(:red).render("Unknown show target '#{target}'. Use '--baseline' or '--mutant'.")
        do_exit(1)
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

      if sub_args.empty? && @selected_rule.nil? && @selected_pattern.nil? && @selected_mutations.nil?
        display_session_setup_status(session)
        return
      end

      i = 0
      modified = false

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
      puts "  next              Generate the next mutated item from session baseline"
      puts "  reward <val>      Provide feedback (-1.0 to 1.0) on the last generated mutant"
      puts "  setup [options]   Configure active rules, mutator pools, patterns, and scopes"
      puts "  show [opts]       Print session baseline or latest mutant (--baseline, --mutant)"
      puts "  history [opts]    Display event history timeline (--limit N, --json)"
      puts "  reset             Reset and delete the session"
      puts "  status [--json]   Display session statistics, iteration count & bandit weights"
      puts "  list [--json]     List all active sessions"
      puts ""
      puts "Workflow Examples:"
      puts "  1. Initialize with input:  \"POST / HTTP/1.1\\r\\n\\r\\n\" | crowbar session 1 next"
      puts "  2. Reward feedback:        crowbar session 1 reward 0.5   (or -0.5)"
      puts "  3. Generate next:          crowbar session 1 next > out.txt"
      puts "  4. Show current mutant:    crowbar session 1 show --mutant"
      puts "  5. View event history:     crowbar session 1 history --limit 10"
      puts "  6. Configure session:      crowbar session 1 setup --add-rule mp3 --set-mutators num,bf"
      puts "  7. Reset session:          crowbar session 1 reset"
      puts "  8. Reset via new input:    \"NEW INPUT\" | crowbar session 1 next"
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
      puts "  --set-mutators <m1,m2>    Restrict mutator pool to comma-separated list"
      puts "  --reset-mutators          Restore default full mutator pool"
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
