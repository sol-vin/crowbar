require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for SQL statements.
  # Preserves overall query grammar skeleton (keywords, clauses, commas, parens)
  # while mutating numeric literals, string literals, comparison operators, and clauses.
  class SQLRule < Rule
    SQL_KEYWORDS = [
      "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
      "WITH", "REPLACE", "MERGE", "TRUNCATE", "EXPLAIN",
    ]

    OPERATORS = ["=", "!=", "<>", ">", "<", ">=", "<=", "LIKE", "NOT LIKE", "IN", "IS"]

    SQLI_PROBES = [
      "'' OR '1'='1",
      "' OR 1=1 --",
      "' UNION SELECT null, null --",
      "admin'/*",
      "' AND SLEEP(5) --",
      "1; DROP TABLE users; --",
      "'\u0000'--",
      "'\u202Eadmin'--",
    ]

    def name : String
      "sql"
    end

    def description : String
      "Structure-preserving SQL statement mutation (preserves syntax, mutates literals & operators)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_raw_s.strip
      return false if str.empty?

      first_word = str.split(/\s+/, 2)[0].upcase
      SQL_KEYWORDS.includes?(first_word)
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      query = buffer.to_raw_s
      return false if query.empty?

      mutated = case context.prng.rand(4)
                when 0
                  # Mutate string literals: 'text'
                  mutate_string_literals(query, context)
                when 1
                  # Mutate numeric literals: \b\d+\b
                  mutate_numeric_literals(query, context)
                when 2
                  # Mutate operators: = to != or LIKE
                  mutate_operators(query, context)
                else
                  # Mutate clauses (e.g. inject LIMIT or boundary expressions)
                  mutate_clauses(query, context)
                end

      return false if mutated == query

      buffer.replace_range(0, buffer.size, mutated.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_string_literals(query : String, context : Context) : String
      string_regex = /'([^'\\]|\\.)*'/
      matches = [] of Regex::MatchData
      query.scan(string_regex) { |m| matches << m }

      return query if matches.empty?

      target_match = context.prng.choice(matches)
      target_range = target_match.byte_begin(0)...target_match.byte_end(0)

      probe = case context.prng.rand(3)
              when 0
                context.prng.choice(SQLI_PROBES)
              when 1
                "'" + ("A" * context.prng.rand(32..256)) + "'"
              else
                "''"
              end

      query[0...target_range.begin] + probe + query[target_range.end..]
    end

    private def mutate_numeric_literals(query : String, context : Context) : String
      num_regex = /\b\d+(\.\d+)?\b/
      matches = [] of Regex::MatchData
      query.scan(num_regex) { |m| matches << m }

      return query if matches.empty?

      target_match = context.prng.choice(matches)
      target_range = target_match.byte_begin(0)...target_match.byte_end(0)

      boundary = context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      query[0...target_range.begin] + boundary + query[target_range.end..]
    end

    private def mutate_operators(query : String, context : Context) : String
      op_regex = /\s(=|!=|<>|>=|<=|>|<|LIKE|IN)\s/i
      matches = [] of Regex::MatchData
      query.scan(op_regex) { |m| matches << m }

      return query if matches.empty?

      target_match = context.prng.choice(matches)
      target_range = target_match.byte_begin(1)...target_match.byte_end(1)

      new_op = context.prng.choice(OPERATORS)
      query[0...target_range.begin] + new_op + query[target_range.end..]
    end

    private def mutate_clauses(query : String, context : Context) : String
      stripped = query.strip.rstrip(';')
      boundary = context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)

      case context.prng.rand(3)
      when 0
        "#{stripped} LIMIT #{boundary};"
      when 1
        "#{stripped} OFFSET #{boundary};"
      else
        "#{stripped} ORDER BY 1 DESC;"
      end
    end
  end
end
