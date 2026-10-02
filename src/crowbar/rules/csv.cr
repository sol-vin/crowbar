require "csv"
require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for CSV / TSV tabular data.
  # Parses delimited records, mutates individual cells, swaps or duplicates columns,
  # or generates boundary test cases (ragged rows, varied delimiters, quoting boundaries).
  class CSVRule < Rule
    def name : String
      "csv"
    end

    def description : String
      "Structure-preserving CSV/TSV tabular data mutation (row/column transforms)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s.strip
      return false if str.empty?
      # Needs at least a comma, tab, or semicolon
      return false unless str.includes?(',') || str.includes?('\t') || str.includes?(';')

      rows = CSV.parse(str)
      rows.size >= 1 && rows.first.size >= 2
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_s
      rows = CSV.parse(raw_str)
      return false if rows.empty?

      # Detect or choose delimiter
      delimiter = raw_str.includes?('\t') ? '\t' : (raw_str.includes?(';') ? ';' : ',')

      case context.prng.rand(5)
      when 0
        # Mutate a cell value
        mutate_cell(rows, context)
      when 1
        # Swap two columns across rows
        swap_columns(rows, context)
      when 2
        # Duplicate a column
        duplicate_column(rows, context)
      when 3
        # Ragged row injection (testing row-length boundary validation)
        inject_ragged_row(rows, context)
      else
        # Delete a column
        delete_column(rows, context)
      end

      # Re-serialize to CSV
      output = CSV.build(separator: delimiter) do |builder|
        rows.each do |row|
          builder.row(row)
        end
      end

      buffer.replace_range(0, buffer.size, output.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_cell(rows : Array(Array(String)), context : Context)
      row_idx = context.prng.rand(rows.size)
      row = rows[row_idx]
      return if row.empty?

      col_idx = context.prng.rand(row.size)
      old_val = row[col_idx]

      new_val = case context.prng.rand(5)
                when 0 then "" # Empty cell
                when 1 then context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
                when 2 then old_val * context.prng.rand(2..4) # Repetition
                when 3 then "\u202E" + old_val                # BiDi override
                else        old_val + "\n" + old_val          # Embedded newline in quoted cell
                end

      row[col_idx] = new_val
    end

    private def swap_columns(rows : Array(Array(String)), context : Context)
      col_count = rows.map(&.size).max? || 0
      return if col_count < 2

      c1 = context.prng.rand(col_count)
      c2 = context.prng.rand(col_count)
      return if c1 == c2

      rows.each do |row|
        if c1 < row.size && c2 < row.size
          row[c1], row[c2] = row[c2], row[c1]
        end
      end
    end

    private def duplicate_column(rows : Array(Array(String)), context : Context)
      col_count = rows.map(&.size).max? || 0
      return if col_count == 0

      src_col = context.prng.rand(col_count)
      rows.each do |row|
        if src_col < row.size
          row.insert(src_col + 1, row[src_col])
        end
      end
    end

    private def delete_column(rows : Array(Array(String)), context : Context)
      col_count = rows.map(&.size).max? || 0
      return if col_count <= 1

      del_col = context.prng.rand(col_count)
      rows.each do |row|
        if del_col < row.size
          row.delete_at(del_col)
        end
      end
    end

    private def inject_ragged_row(rows : Array(Array(String)), context : Context)
      return if rows.size < 2
      # Pick a data row (skip header)
      row_idx = context.prng.rand(1...rows.size)
      row = rows[row_idx]

      if context.prng.rand_bool && row.size > 1
        # Drop a column from just this row
        row.delete_at(context.prng.rand(row.size))
      else
        # Append an unexpected extra cell to just this row
        row << context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      end
    end
  end
end
