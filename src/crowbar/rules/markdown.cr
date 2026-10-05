require "./base"

module Crowbar::Rules
  # Structure-preserving rule for CommonMark and Markdown documents.
  # Preserves markdown syntax trees, frontmatter, and block hierarchies while mutating
  # link destinations, image sources, code fence tags, table delimiter rows,
  # ATX/Setext heading levels, and nested lists.
  class MarkdownRule < Rule
    def name : String
      "markdown"
    end

    def description : String
      "Structure-preserving CommonMark/Markdown with link, table, heading, and fence mutations"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s
      return false if str.size < 5

      # Check for Markdown indicators: headings, links, code blocks, tables, or blockquotes
      has_heading = str.includes?("# ") || str.includes?("## ") || str.includes?("\n===") || str.includes?("\n---")
      has_link = str.includes?("](") || str.includes?("![")
      has_fence = str.includes?("```") || str.includes?("~~~")
      has_table = str.includes?("| ---") || str.includes?("|:---") || (str.includes?("|") && str.includes?("\n|"))
      has_quote = str.starts_with?("> ") || str.includes?("\n> ")

      has_heading || has_link || has_fence || has_table || has_quote
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      text = buffer.to_s
      action = context.prng.rand(5)
      mutated_text : String? = nil

      case action
      when 0
        # Mutate Markdown Links and Images: [label](url) -> mutate url or label
        if text.includes?("](")
          mutated_text = text.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do |match, (label, url)|
            if context.prng.rand_bool
              # Mutate destination URL with boundary probes
              bad_urls = [
                "javascript:alert(1)",
                "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
                "../../../../../../etc/passwd",
                "http://example.com/" + ("A" * 500),
                "https://%00evil.com",
                "%s%s%s%s%s%s%s%s",
                "file:///etc/shadow",
              ]
              "[#{label}](#{context.prng.choice(bad_urls)})"
            else
              # Mutate link label text
              "[#{label * context.prng.rand(2..5)}](#{url})"
            end
          end
        end
      when 1
        # Mutate ATX / Setext Headings (# Heading)
        if text.includes?("# ") || text.includes?("## ")
          mutated_text = text.gsub(/^(#+)\s+(.+)$/m) do |match, (hashes, title)|
            case context.prng.rand(3)
            when 0
              # Deep heading nesting boundary probe (# x 100)
              ("#" * context.prng.choice([1, 6, 50, 255])) + " " + title
            when 1
              # Empty heading
              hashes + " "
            else
              # Format string or null byte probe in heading title
              hashes + " " + title + "\0" + "%n%s%x"
            end
          end
        end
      when 2
        # Mutate Fenced Code Blocks (```lang ... ```)
        if text.includes?("```")
          mutated_text = text.gsub(/```([a-zA-Z0-9_\-]*)\n([\s\S]*?)\n```/) do |match, (lang, body)|
            case context.prng.rand(3)
            when 0
              # Mutate fence language identifier
              bad_langs = ["A" * 200, "ruby\0injected", "../../traversal", "<script>", "%s%s%s"]
              "```#{context.prng.choice(bad_langs)}\n#{body}\n```"
            when 1
              # Unclosed fence delimiter probe (EOF fuzzing)
              "```#{lang}\n#{body}\n"
            else
              # Quadruple backticks and nested code fence
              "````#{lang}\n#{body}\n````"
            end
          end
        end
      when 3
        # Mutate Markdown Tables (| Col 1 | Col 2 |)
        if text.includes?("|")
          lines = text.split("\n")
          table_lines = lines.map do |line|
            if line.strip.starts_with?("|") && line.strip.ends_with?("|")
              cells = line.split("|")
              if cells.size > 2
                case context.prng.rand(3)
                when 0
                  # Add duplicate cell
                  cells.insert(context.prng.rand(1...cells.size), " Injected Column ")
                  cells.join("|")
                when 1
                  # Inject huge cell padding
                  cells[1] = " " + ("X" * 100) + " "
                  cells.join("|")
                else
                  line
                end
              else
                line
              end
            else
              line
            end
          end
          mutated_text = table_lines.join("\n")
        end
      else
        # Mutate Blockquotes and Nested Formatting
        if text.includes?("> ")
          mutated_text = text.gsub(/^>\s+(.*)$/m) do |_, (quote_body)|
            # Deeply nested blockquotes (> > > > ...)
            (">" * context.prng.rand(10..50)) + " " + quote_body
          end
        else
          # Fallback: duplicate list items or emphasis
          mutated_text = text.gsub(/^([*\-+])\s+(.*)$/m) do |match, (bullet, item)|
            "#{bullet} #{item}\n#{bullet} #{item} (duplicate)"
          end
        end
      end

      # Fallback if specific pattern was not matched in text
      if mutated_text.nil? || mutated_text == text
        mutated_text = text + "\n\n<!-- Fuzz Probe: " + ("A" * 64) + " -->\n"
      end

      buffer.replace_range(0, buffer.size, mutated_text.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end
  end
end
