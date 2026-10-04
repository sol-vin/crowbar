require "json"
require "opal"
require "../rules/registry"
require "../patterns/base"
require "../mutators/pool"

module Crowbar::CLI
  # Formats and renders component catalogs for CLI output (Opal terminal formatting or JSON)
  module CatalogView
    def self.render_catalog(io : IO, json : Bool = false)
      if json
        data = {
          "rules" => Rules::Registry.catalog.map do |entry|
            {
              "name"        => entry.name,
              "description" => entry.description,
              "aliases"     => entry.aliases,
            }
          end,
          "patterns" => Patterns.catalog.map do |(name, code, desc)|
            {
              "name"        => name,
              "code"        => code,
              "description" => desc,
            }
          end,
          "mutators" => MutatorPool.new.mutators.map do |m|
            {
              "name"        => m.name,
              "description" => m.description,
              "aliases"     => m.aliases,
            }
          end,
        }
        io.puts data.to_pretty_json
        return
      end

      title_style = Opal.style.bold.fg(:cyan)
      category_style = Opal.style.bold.fg(:yellow)
      dim_style = Opal.style.fg(:bright_black)
      name_style = Opal.style.bold.fg(:green)

      io.puts title_style.render("=== Crowbar Component Catalog ===")
      io.puts ""

      # 1. Structure-Preserving Rules
      io.puts category_style.render("Structure-Preserving Rules (#{Rules::Registry.catalog.size} Formats):")
      Rules::Registry.catalog.each do |entry|
        alias_str = entry.aliases.empty? ? "" : " (aliases: #{entry.aliases.join(", ")})"
        io.puts sprintf("  %-10s %s%s", name_style.render(entry.name), dim_style.render(entry.description), dim_style.render(alias_str))
      end
      io.puts ""

      # 2. Execution Patterns
      io.puts category_style.render("Mutation Patterns:")
      patterns = [
        {"od, once", "Single mutation applied per iteration"},
        {"nd, many", "Multiple mutations with geometric decay (default)"},
        {"bu, burst", "Localized burst of adjacent mutations"},
      ]
      patterns.each do |(code, desc)|
        io.puts sprintf("  %-10s %s", name_style.render(code), dim_style.render(desc))
      end
      io.puts ""

      # 3. Mutator Families
      pool = MutatorPool.new
      io.puts category_style.render("Mutators (#{pool.mutators.size} Total):")
      pool.mutators.each do |m|
        alias_info = m.aliases.empty? ? "" : " (aliases: #{m.aliases.join(", ")})"
        io.puts sprintf("  %-10s %s%s", name_style.render(m.name), dim_style.render(m.description), dim_style.render(alias_info))
      end
      io.puts ""

      # 4. Scopes & Selectors
      io.puts category_style.render("Selectors & Combinators:")
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
        io.puts sprintf("  %-10s %s", name_style.render(code), dim_style.render(desc))
      end
      io.puts ""
    end

    def self.render_rules(io : IO, json : Bool = false)
      if json
        data = Rules::Registry.catalog.map do |entry|
          {
            "name"        => entry.name,
            "description" => entry.description,
            "aliases"     => entry.aliases,
          }
        end
        io.puts data.to_pretty_json
        return
      end

      title_style = Opal.style.bold.fg(:cyan)
      dim_style = Opal.style.fg(:bright_black)
      name_style = Opal.style.bold.fg(:green)

      io.puts title_style.render("Available Format Rules:")
      Rules::Registry.catalog.each do |entry|
        alias_str = entry.aliases.empty? ? "" : " [aliases: #{entry.aliases.join(", ")}]"
        io.puts sprintf("  %-10s %s%s", name_style.render(entry.name), dim_style.render(entry.description), dim_style.render(alias_str))
      end
    end

    def self.render_mutators(io : IO, json : Bool = false)
      if json
        data = MutatorPool.new.mutators.map do |m|
          {
            "name"        => m.name,
            "description" => m.description,
            "aliases"     => m.aliases,
          }
        end
        io.puts data.to_pretty_json
        return
      end

      title_style = Opal.style.bold.fg(:cyan)
      dim_style = Opal.style.fg(:bright_black)
      name_style = Opal.style.bold.fg(:green)

      io.puts title_style.render("Available Mutators:")
      pool = MutatorPool.new
      pool.mutators.each do |m|
        alias_info = m.aliases.empty? ? "" : " (aliases: #{m.aliases.join(", ")})"
        io.puts sprintf("  %-10s %s%s", name_style.render(m.name), dim_style.render(m.description), dim_style.render(alias_info))
      end
    end
  end
end
