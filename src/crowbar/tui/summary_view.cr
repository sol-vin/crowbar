require "opal"
require "json"
require "../session"

module Crowbar::TUI
  # Non-interactive / scripted summary renderer for session review and breakdown.
  # Provides human-readable terminal tables or machine-readable JSON for CI and automated pipelines.
  class SummaryView
    def self.render(session : Session, io : IO = STDOUT, limit : Int32 = 25, json : Bool = false) : Nil
      if json
        render_json(session, io)
      else
        render_table(session, io, limit)
      end
    end

    private def self.render_json(session : Session, io : IO) : Nil
      data = {
        "session_id"    => session.id,
        "created_at"    => session.created_at.to_s,
        "updated_at"    => session.updated_at.to_s,
        "iteration"     => session.iteration,
        "baseline_size" => session.baseline.size,
        "active_rules"  => session.active_rules,
        "template"      => session.template,
        "items_count"   => session.items.size,
        "corpus_count"  => session.corpus_items.size,
        "items"         => session.items.map do |item|
          {
            "iteration"  => item.iteration,
            "timestamp"  => item.timestamp.to_s,
            "size"       => item.size,
            "diff_count" => item.diff_count,
            "mutators"   => item.mutators,
            "reward"     => item.reward,
            "seed"       => item.seed.to_s,
            "seek"       => item.seek_offset,
            "steps"      => item.steps.map do |s|
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
        end,
        "arms" => session.arms.map do |k, arm|
          {
            "name"    => k,
            "pulls"   => arm.pulls,
            "rewards" => arm.rewards,
          }
        end,
      }
      io.puts data.to_pretty_json
    end

    private def self.render_table(session : Session, io : IO, limit : Int32) : Nil
      title_style = Opal.style.bold.fg(:cyan)
      header_style = Opal.style.fg(:bright_black)
      label_style = Opal.style.bold.fg(:yellow)
      green_style = Opal.style.fg(:green)
      red_style = Opal.style.fg(:red)
      dim_style = Opal.style.fg(:bright_black)
      bold_style = Opal.style.bold

      io.puts title_style.render("=== Crowbar Session Reviewer: #{session.id} ===")
      io.puts header_style.render(
        sprintf(
          "Baseline: %d B | Iterations: %d | Items Tracked: %d | Corpus: %d",
          session.baseline.size,
          session.iteration,
          session.items.size,
          session.corpus_items.size
        )
      )
      rules_str = session.active_rules.empty? ? "none" : session.active_rules.join(", ")
      enc_str = sprintf("In: %s | Out: %s", session.input_encoding || "raw", session.output_encoding || "raw")
      io.puts dim_style.render("Rules: #{rules_str} | Encodings: #{enc_str}")
      io.puts dim_style.render("-" * 78)

      if session.items.empty?
        io.puts Opal.style.fg(:yellow).render("No items recorded yet in session '#{session.id}'.")
        io.puts "Generate mutants first: echo 'sample' | crowbar session #{session.id} next"
        return
      end

      # Table Header
      io.puts sprintf(
        " %-5s | %-8s | %-8s | %-6s | %-16s | %-8s | %s",
        bold_style.render("#"),
        bold_style.render("Time"),
        bold_style.render("Size"),
        bold_style.render("Diff"),
        bold_style.render("Mutators"),
        bold_style.render("Reward"),
        bold_style.render("Primary Transformation")
      )
      io.puts dim_style.render("-" * 78)

      # Render item rows
      displayed = session.items.last(limit)
      displayed.each do |item|
        rwd_str = if r = item.reward
                    r > 0 ? green_style.render(sprintf("+%.2f", r)) : red_style.render(sprintf("%.2f", r))
                  else
                    dim_style.render("  --  ")
                  end

        time_str = item.timestamp.to_s("%H:%M:%S")
        size_str = sprintf("%d B", item.size)
        diff_str = sprintf("+%d B", item.diff_count)
        muts_str = item.mutators.empty? ? "none" : item.mutators.join(",")
        muts_str = muts_str[0, 15] + "…" if muts_str.size > 16

        primary_step = item.steps.find { |s| s.category == StepCategory::Mutator || s.category == StepCategory::Rule }
        step_desc = if primary_step
                      "#{primary_step.category.to_badge} #{primary_step.description}"
                    elsif !item.steps.empty?
                      "#{item.steps.first.category.to_badge} #{item.steps.first.description}"
                    else
                      dim_style.render("Standard transformation")
                    end
        step_desc = step_desc[0, 30] + "…" if step_desc.size > 31

        io.puts sprintf(
          " %-5d | %-8s | %-8s | %-6s | %-16s | %-8s | %s",
          item.iteration,
          dim_style.render(time_str),
          size_str,
          item.diff_count > 0 ? label_style.render(diff_str) : dim_style.render(" 0 B"),
          muts_str,
          rwd_str,
          step_desc
        )
      end

      io.puts dim_style.render("-" * 78)

      # Top Mutators by Credit
      if !session.arms.empty?
        io.puts bold_style.render("Active Multi-Armed Bandit Mutators:")
        top_arms = session.arms.to_a.sort_by { |_, a| -a.rewards }.first(5)
        top_arms.each do |name, arm|
          io.puts sprintf("  %-10s | Pulls: %-5d | Rewards: %+.2f", name, arm.pulls, arm.rewards)
        end
        io.puts ""
      end

      # Hints
      io.puts dim_style.render("Replay item: crowbar session #{session.id} replay <#>")
      io.puts dim_style.render("Reward item: crowbar session #{session.id} reward <value> -i <#>")
      io.puts dim_style.render("Inspect payload: crowbar session #{session.id} show <#>")
    end
  end
end
