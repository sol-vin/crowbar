require "opal"
require "json"
require "./analyzer"

module Crowbar::Inspector
  # Renders diagnostic inspection reports to terminal (Opal styled) or JSON.
  class View
    def self.render(report : InspectionReport, io : IO = STDOUT, json : Bool = false) : Nil
      if json
        io.puts report.to_pretty_json
      else
        render_terminal(report, io)
      end
    end

    private def self.render_terminal(report : InspectionReport, io : IO) : Nil
      title_style = Opal.style.bold.fg(:cyan)
      header_style = Opal.style.fg(:bright_black)
      label_style = Opal.style.bold.fg(:yellow)
      green_style = Opal.style.fg(:green)
      red_style = Opal.style.fg(:red)
      dim_style = Opal.style.fg(:bright_black)
      bold_style = Opal.style.bold

      target_name = report.filename || (report.session_id ? "Session #{report.session_id}" : "Buffer")
      io.puts title_style.render("=== Crowbar Diagnostic Inspector ===")
      io.puts sprintf(
        "Target: %s | Size: %s B | Format: %s",
        bold_style.render(target_name),
        label_style.render(report.size.to_s),
        green_style.render(report.format || "Raw / Binary")
      )

      if magic = report.details["magic_hex"]?
        io.puts dim_style.render("Magic Bytes: #{magic}")
      end
      io.puts dim_style.render("-" * 78)

      # 1. Structural Boundaries
      if !report.boundaries.empty?
        io.puts bold_style.render("Structural Format Boundaries:")
        report.boundaries.each do |b|
          valid_badge = if b.valid == true
                          green_style.render("[OK]")
                        elsif b.valid == false
                          red_style.render("[INVALID]")
                        else
                          ""
                        end
          range_str = sprintf("[0x%04X - 0x%04X]", b.offset_start, [0, b.offset_end - 1].max)
          io.puts sprintf(
            "  %-17s  %-20s %s %s",
            dim_style.render(range_str),
            label_style.render(b.name),
            b.description,
            valid_badge
          )
        end
        io.puts dim_style.render("-" * 78)
      end

      # 2. Shannon Entropy Profiling
      io.puts bold_style.render("Shannon Entropy Distribution:")
      io.puts sprintf(
        "  %-5s  %-17s  %-8s  %-18s  %s",
        dim_style.render("Block"),
        dim_style.render("Offset Range"),
        dim_style.render("Entropy"),
        dim_style.render("Profile"),
        dim_style.render("Density Bar")
      )

      report.entropy_blocks.each do |eb|
        range_str = sprintf("0x%04X - 0x%04X", eb.offset_start, [0, eb.offset_end - 1].max)
        bar = eb.visual_bar(16)
        colored_bar = if eb.entropy >= 7.5
                        red_style.render(bar)
                      elsif eb.entropy >= 6.0
                        label_style.render(bar)
                      elsif eb.entropy >= 3.5
                        green_style.render(bar)
                      else
                        dim_style.render(bar)
                      end

        io.puts sprintf(
          "   %02d    %-17s  %-8.2f  %-18s  %s %.2f",
          eb.index,
          range_str,
          eb.entropy,
          dim_style.render(eb.classification),
          colored_bar,
          eb.entropy
        )
      end

      overall_class = if report.overall_entropy >= 7.5
                        red_style.render("High Density / Compressed / Encrypted")
                      elsif report.overall_entropy >= 4.0
                        green_style.render("Structured Code / Text")
                      else
                        dim_style.render("Low Density / Sparse")
                      end

      io.puts dim_style.render("-" * 78)
      io.puts sprintf("Overall Shannon Entropy: %s bits/byte (%s)", label_style.render(report.overall_entropy.to_s), overall_class)

      # 3. Session Mutation Heatmap
      if heat = report.heatmap
        io.puts dim_style.render("-" * 78)
        io.puts bold_style.render("Session Mutation Heatmap (Byte-Offset Hit Frequency):")
        io.puts dim_style.render("Scale: [.] 0 hits   [cyan] 1-2 hits   [yellow] 3-5 hits   [red] 6+ hits")
        io.puts ""

        cols = 16
        total = heat.size
        i = 0
        while i < total
          chunk_end = [i + cols, total].min
          slice = heat[i...chunk_end]

          hex_tokens = slice.map do |count|
            if count == 0
              dim_style.render(" .")
            elsif count <= 2
              Opal.style.fg(:cyan).render(sprintf("%2d", count))
            elsif count <= 5
              label_style.render(sprintf("%2d", count))
            else
              Opal.style.bold.fg(:red).render(sprintf("%2d", count))
            end
          end

          offset_str = sprintf("%04X:", i)
          io.puts sprintf("  %s  %s", dim_style.render(offset_str), hex_tokens.join(" "))
          i += cols
        end

        mutated_count = heat.count { |c| c > 0 }
        pct = total > 0 ? (mutated_count.to_f64 / total * 100.0).round(1) : 0.0
        max_hits = heat.max? || 0

        io.puts ""
        io.puts sprintf(
          "Coverage: %d / %d bytes (%s%%) mutated | Peak Hotspot: %s hits",
          mutated_count,
          total,
          label_style.render(pct.to_s),
          red_style.render(max_hits.to_s)
        )
      end
    end
  end
end
