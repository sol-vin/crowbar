require "opal"
require "../buffer"

module Crowbar::CLI
  # Terminal hex diff viewer powered by Opal TrueColor styling.
  module HexDiff
    def self.render(original : Buffer, mutated : Buffer, io : IO = STDOUT)
      title_style = Opal.style.bold.fg(:cyan)
      header_style = Opal.style.fg(:bright_black)
      diff_style = Opal.style.bold.fg(:yellow)
      orig_byte_style = Opal.style.fg(:red)
      mut_byte_style = Opal.style.bold.fg(:green)
      dim_style = Opal.style.fg(:bright_black)

      io.puts title_style.render("=== Crowbar Hex Diff ===")
      io.puts header_style.render(sprintf("Original Size: %d B | Mutated Size: %d B", original.size, mutated.size))
      io.puts dim_style.render("-" * 64)

      max_size = [original.size, mutated.size].max
      chunk_size = 16

      (0...max_size).step(chunk_size) do |offset|
        # Check if this row has any difference
        row_has_diff = false
        (0...chunk_size).each do |i|
          idx = offset + i
          b_orig = original[idx]?
          b_mut = mutated[idx]?
          if b_orig != b_mut
            row_has_diff = true
            break
          end
        end

        row_prefix = sprintf("%08X: ", offset)
        if row_has_diff
          io.print diff_style.render(row_prefix)
        else
          io.print dim_style.render(row_prefix)
        end

        # Hex column (mutated)
        (0...chunk_size).each do |i|
          idx = offset + i
          b_orig = original[idx]?
          b_mut = mutated[idx]?

          if b_mut
            hex_str = sprintf("%02X ", b_mut)
            if b_orig != b_mut
              io.print mut_byte_style.render(hex_str)
            else
              io.print hex_str
            end
          else
            io.print "   "
          end

          io.print " " if i == 7
        end

        io.print " |"

        # ASCII column
        (0...chunk_size).each do |i|
          idx = offset + i
          b_orig = original[idx]?
          b_mut = mutated[idx]?

          if b_mut
            char_str = (b_mut >= 32 && b_mut <= 126) ? b_mut.unsafe_chr.to_s : "."
            if b_orig != b_mut
              io.print mut_byte_style.render(char_str)
            else
              io.print char_str
            end
          else
            io.print " "
          end
        end

        io.puts "|"
      end

      io.puts dim_style.render("-" * 64)
    end

    # Renders up to max_lines of diff lines for TUI or constrained viewports
    def self.render_lines(original : Buffer, mutated : Buffer, max_lines : Int32 = 20) : Array(String)
      lines = [] of String
      diff_style = Opal.style.bold.fg(:yellow)
      orig_byte_style = Opal.style.fg(:red)
      mut_byte_style = Opal.style.bold.fg(:green)
      dim_style = Opal.style.fg(:bright_black)

      max_size = [original.size, mutated.size].max
      chunk_size = 16

      (0...max_size).step(chunk_size) do |offset|
        break if lines.size >= max_lines

        row_has_diff = false
        (0...chunk_size).each do |i|
          idx = offset + i
          if original[idx]? != mutated[idx]?
            row_has_diff = true
            break
          end
        end

        row_io = IO::Memory.new
        row_prefix = sprintf("%06X: ", offset)
        row_io.print(row_has_diff ? diff_style.render(row_prefix) : dim_style.render(row_prefix))

        (0...chunk_size).each do |i|
          idx = offset + i
          b_orig = original[idx]?
          b_mut = mutated[idx]?

          if b_mut
            hex_str = sprintf("%02X ", b_mut)
            row_io.print(b_orig != b_mut ? mut_byte_style.render(hex_str) : hex_str)
          else
            row_io.print "   "
          end
          row_io.print " " if i == 7
        end

        row_io.print " |"
        (0...chunk_size).each do |i|
          idx = offset + i
          b_orig = original[idx]?
          b_mut = mutated[idx]?

          if b_mut
            char_str = (b_mut >= 32 && b_mut <= 126) ? b_mut.unsafe_chr.to_s : "."
            row_io.print(b_orig != b_mut ? mut_byte_style.render(char_str) : char_str)
          else
            row_io.print " "
          end
        end
        row_io.print "|"
        lines << row_io.to_s
      end

      lines
    end
  end
end
