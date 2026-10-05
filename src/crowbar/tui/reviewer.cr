require "opal"
require "../session"
require "../cli/diff"

module Crowbar::TUI
  # Interactive Terminal User Interface for reviewing session items,
  # inspecting side-by-side hex diffs, examining transformation provenance,
  # and applying deferred rewards to any past iteration.
  class ReviewerModel
    include Opal::TEA::Model

    getter session : Session
    property selected_index : Int32 = 0
    property active_tab : Int32 = 0 # 0: Hex Diff, 1: Process Breakdown, 2: Replay & Payload
    property status_message : String? = nil
    property reward_mode : Bool = false
    property reward_buffer : String = ""
    property diff_mode : Symbol = :hex
    property filter_mode : Symbol = :all
    property width : Int32 = 100
    property height : Int32 = 28
    property session_dir : String = Session.default_dir

    def initialize(
      @session : Session,
      @session_dir : String = Session.default_dir,
      @width : Int32 = 100,
      @height : Int32 = 28,
    )
      # Clamp selected index to available items
      @selected_index = [0, @session.items.size - 1].min
    end

    def init : Opal::TEA::Cmd
      Opal::TEA::Cmd.none
    end

    def filtered_items : Array(SessionItem)
      case @filter_mode
      when :rewarded
        @session.items.select(&.rewarded?)
      when :unrewarded
        @session.items.reject(&.rewarded?)
      else
        @session.items
      end
    end

    def current_selected_item : SessionItem?
      items = filtered_items
      return nil if items.empty?
      idx = [[0, @selected_index].max, items.size - 1].min
      items[idx]?
    end

    def update(msg : Opal::TEA::Msg) : {Opal::TEA::Model, Opal::TEA::Cmd}
      case msg
      when Opal::TEA::WindowSizeMsg
        @width = [msg.width, 80].max
        @height = [msg.height, 20].max
        {self, Opal::TEA::Cmd.none}
      when Opal::TEA::KeyMsg
        key = msg.key.downcase

        if @reward_mode
          case key
          when "enter"
            val = @reward_buffer.strip.empty? ? 1.0 : (@reward_buffer.to_f64? || 1.0)
            if item = current_selected_item
              @session.reward(val, item.iteration, @session_dir)
              @status_message = "Rewarded item ##{item.iteration} with #{val > 0 ? "+" : ""}#{val} (Bandit & Corpus updated)"
            end
            @reward_mode = false
            @reward_buffer = ""
          when "escape", "esc"
            @reward_mode = false
            @reward_buffer = ""
          when "backspace"
            @reward_buffer = @reward_buffer[0...-1] unless @reward_buffer.empty?
          else
            # Allow digits, signs, and decimal point
            if msg.key.size == 1 && (msg.key.matches?(/[0-9\.\+\-]/))
              @reward_buffer += msg.key
            end
          end
          return {self, Opal::TEA::Cmd.none}
        end

        items = filtered_items
        max_idx = [0, items.size - 1].max

        case key
        when "up", "k"
          @selected_index = [@selected_index - 1, 0].max
        when "down", "j"
          @selected_index = [@selected_index + 1, max_idx].min
        when "pageup"
          @selected_index = [@selected_index - 10, 0].max
        when "pagedown"
          @selected_index = [@selected_index + 10, max_idx].min
        when "home"
          @selected_index = 0
        when "end"
          @selected_index = max_idx
        when "1"
          @active_tab = 0
        when "2"
          @active_tab = 1
        when "3"
          @active_tab = 2
        when "tab"
          @active_tab = (@active_tab + 1) % 3
        when "r", "+"
          if current_selected_item
            @reward_mode = true
            @reward_buffer = "+1.0"
          end
        when "-"
          if item = current_selected_item
            @session.reward(-1.0, item.iteration, @session_dir)
            @status_message = "Penalized item ##{item.iteration} with -1.0 (Bandit arms debited)"
          end
        when "e"
          if item = current_selected_item
            if buf = @session.get_mutant(item.iteration, @session_dir)
              fname = "mutant_#{@session.id}_iter_#{item.iteration}.bin"
              File.write(fname, buf.to_slice)
              @status_message = "Exported item ##{item.iteration} to #{fname} (#{buf.size} B)"
            end
          end
        when "d"
          @diff_mode = (@diff_mode == :hex ? :text : :hex)
        when "f"
          @filter_mode = case @filter_mode
                         when :all      then :rewarded
                         when :rewarded then :unrewarded
                         else                :all
                         end
          @selected_index = 0
        when "q", "ctrl+c", "escape", "esc"
          return {self, Opal::TEA::Cmd.quit}
        end

        {self, Opal::TEA::Cmd.none}
      else
        {self, Opal::TEA::Cmd.none}
      end
    end

    def view : String
      items = filtered_items
      curr_item = current_selected_item

      Opal.render_ui(width: @width, height: @height) do |ui|
        ui.box(border: :rounded, title: "Crowbar Session Reviewer: #{@session.id}", title_fg: :cyan, padding: 0) do |root_box|
          root_box.vstack(spacing: 0) do |v|
            # 1. Header Toolbar
            v.hstack(spacing: 2) do
              v.badge "SESSION: #{@session.id}", bg: :cyan, fg: :black
              v.text "Baseline: #{@session.baseline.size} B", bold: true
              v.text "Items: #{@session.items.size}", fg: :yellow
              v.text "Corpus: #{@session.corpus_items.size}", fg: :green
              v.text "Filter: #{@filter_mode.to_s.upcase}", fg: :bright_magenta
              if @session.active_rules.size > 0
                v.text "Rules: #{@session.active_rules.join(",")}", dim: true
              end
            end

            v.rule

            # 2. Main Content Area (Two Columns: Items List on Left, Detail on Right)
            left_w = 42
            v.hstack(spacing: 1) do |h|
              # LEFT PANE: Iterations Table
              h.box(title: "Iterations (#{items.size})", border: :rounded) do |lb|
                lb.table(headers: ["", "Iter", "Muts", "Size", "Rwd"]) do |t|
                  if items.empty?
                    t.row ["", "none", "--", "--", "--"]
                  else
                    # Show slice around selected_index
                    viewport_h = [@height - 10, 5].max
                    start_i = [@selected_index - (viewport_h // 2), 0].max
                    end_i = [start_i + viewport_h, items.size].min
                    start_i = [end_i - viewport_h, 0].max if end_i == items.size

                    (start_i...end_i).each do |i|
                      it = items[i]
                      cursor = (i == @selected_index) ? "▸" : " "
                      iter_lbl = "##{it.iteration}"
                      muts = it.mutators.empty? ? "-" : it.mutators.first(2).join(",")
                      muts = muts[0, 10] if muts.size > 10
                      sz_lbl = "#{it.size}B"
                      rwd_lbl = if r = it.reward
                                  r > 0 ? "+#{r.round(1)}" : "#{r.round(1)}"
                                else
                                  "--"
                                end
                      t.row [cursor, iter_lbl, muts, sz_lbl, rwd_lbl]
                    end
                  end
                end
              end

              # RIGHT PANE: Detail Tabs
              h.box(title: tab_title, border: :rounded) do |rb|
                rb.vstack(spacing: 0) do |rv|
                  # Tab Navigation Bar
                  rv.hstack(spacing: 2) do
                    rv.text "1: Hex Diff", bold: @active_tab == 0, fg: @active_tab == 0 ? :cyan : :white
                    rv.text "2: Steps", bold: @active_tab == 1, fg: @active_tab == 1 ? :cyan : :white
                    rv.text "3: Replay", bold: @active_tab == 2, fg: @active_tab == 2 ? :cyan : :white
                  end
                  rv.rule

                  # Render active tab body
                  if it = curr_item
                    case @active_tab
                    when 0
                      render_diff_tab(rv, it)
                    when 1
                      render_steps_tab(rv, it)
                    when 2
                      render_replay_tab(rv, it)
                    end
                  else
                    rv.text "No item selected", dim: true
                  end
                end
              end
            end

            v.rule

            # 3. Footer Bar
            if @reward_mode
              v.hstack(spacing: 2) do
                v.badge "REWARD INPUT", bg: :green, fg: :black
                v.text "Score for Item ##{curr_item.try(&.iteration)}: [#{@reward_buffer}]  (Press Enter to confirm, Esc to cancel)", bold: true
              end
            else
              v.hstack(spacing: 2) do
                if msg = @status_message
                  v.text msg, fg: :green, bold: true
                else
                  v.text "[↑/↓] Select", dim: true
                  v.text "[r/+] Reward", fg: :green
                  v.text "[-] Penalize", fg: :red
                  v.text "[1-3] Tabs", dim: true
                  v.text "[e] Export", fg: :cyan
                  v.text "[f] Filter", dim: true
                  v.text "[q] Quit", dim: true
                end
              end
            end
          end
        end
      end
    end

    private def tab_title : String
      if it = current_selected_item
        case @active_tab
        when 0 then "Item ##{it.iteration} — Hex Diff (#{it.diff_count} B changed)"
        when 1 then "Item ##{it.iteration} — Transformation Breakdown (#{it.steps.size} steps)"
        when 2 then "Item ##{it.iteration} — Deterministic Replay & Output"
        else        "Item Details"
        end
      else
        "Details"
      end
    end

    private def render_diff_tab(v, item : SessionItem)
      mutant = @session.get_mutant(item.iteration, @session_dir)
      unless mutant
        v.text "Mutant binary not found on disk or could not be replayed.", fg: :yellow
        return
      end

      max_diff_lines = [@height - 12, 6].max
      diff_lines = Crowbar::CLI::HexDiff.render_lines(@session.baseline, mutant, max_lines: max_diff_lines)

      if diff_lines.empty?
        v.text "Identical to baseline (0 byte delta).", dim: true
      else
        diff_lines.each do |line|
          v.text line
        end
      end
    end

    private def render_steps_tab(v, item : SessionItem)
      if item.steps.empty?
        v.text "No detailed transformation steps captured for this item.", dim: true
        v.text "Mutators: #{item.mutators.join(", ")}"
        return
      end

      max_steps = [@height - 12, 6].max
      item.steps.first(max_steps).each do |s|
        v.hstack(spacing: 1) do
          v.badge s.category.to_badge, bg: badge_color(s.category), fg: :black
          v.text "#{s.name}: #{s.description}", bold: s.category == StepCategory::Mutator
          if s.diff_bytes != 0
            v.text "(#{s.diff_string})", fg: s.diff_bytes > 0 ? :yellow : :red
          end
        end
      end
    end

    private def render_replay_tab(v, item : SessionItem)
      v.text "Replay CLI Command:", bold: true
      v.text "  crowbar session #{@session.id} replay #{item.iteration}", fg: :cyan
      v.text "Inspect Payload:", bold: true
      v.text "  crowbar session #{@session.id} show #{item.iteration}", fg: :cyan
      v.rule
      v.text "Coordinates:", bold: true
      v.text "  Seed:        0x#{item.seed.to_s(16).upcase}"
      v.text "  Seek Offset: #{item.seek_offset}"
      v.text "  Mutators:    #{item.mutators.join(", ")}"
      v.text "  Size:        #{item.size} B (Delta: #{item.diff_count} B)"
      rwd_str = item.reward ? sprintf("%+.2f", item.reward.not_nil!) : "None"
      v.text "  Reward:      #{rwd_str}", fg: item.positive_reward? ? :green : :white
    end

    private def badge_color(cat : StepCategory) : Symbol
      case cat
      when StepCategory::Parent     then :blue
      when StepCategory::Selector   then :magenta
      when StepCategory::Mutator    then :yellow
      when StepCategory::Rule       then :cyan
      when StepCategory::Fixup      then :green
      when StepCategory::Template   then :bright_blue
      when StepCategory::Uniqueness then :bright_magenta
      else                               :white
      end
    end
  end

  # Helper launcher to run the TUI reviewer with Opal TEA program
  class Reviewer
    def self.run(session : Session, session_dir : String = Session.default_dir, driver : Opal::Terminal::Driver? = nil) : Nil
      model = ReviewerModel.new(session, session_dir: session_dir)
      program = Opal::TEA::Program.new(model, driver: driver, alt_screen: true, mouse_enabled: false)
      program.run
    end
  end
end
