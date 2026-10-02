require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for HTTP/1.x messages.
  # Parses Start Line, Headers, and Body, maintaining proper CRLF line framing
  # while mutating paths, query parameters, header values, or body content.
  class HTTPRule < Rule
    def name : String
      "http"
    end

    def description : String
      "Structure-preserving HTTP/1.x message mutation (valid framing with mutated headers/body)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_raw_s
      str.starts_with?("GET ") || str.starts_with?("POST ") ||
        str.starts_with?("PUT ") || str.starts_with?("DELETE ") ||
        str.starts_with?("HEAD ") || str.starts_with?("OPTIONS ") ||
        str.starts_with?("HTTP/1.")
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_raw_s
      crlf_split = raw_str.split("\r\n\r\n", 2)
      header_section = crlf_split[0]
      body_section = crlf_split.size > 1 ? crlf_split[1] : ""

      header_lines = header_section.split("\r\n")
      return false if header_lines.empty?

      start_line = header_lines[0]
      headers = header_lines[1..]

      case context.prng.rand(4)
      when 0
        # Mutate Start Line (Path / Query string / Method)
        start_line = mutate_start_line(start_line, context)
      when 1
        # Mutate Header Values
        headers = mutate_headers(headers, context)
      when 2
        # Duplicate or reorder headers
        headers = duplicate_or_reorder_headers(headers, context)
      else
        # Mutate Body
        body_section = mutate_body(body_section, context)
      end

      # Reconstruct HTTP message with strict CRLF framing
      io = IO::Memory.new
      io << start_line << "\r\n"
      headers.each do |h|
        io << h << "\r\n"
      end
      io << "\r\n"
      io << body_section

      reconstructed = io.to_slice
      buffer.replace_range(0, buffer.size, reconstructed)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_start_line(start_line : String, context : Context) : String
      parts = start_line.split(" ", 3)
      return start_line if parts.size < 2

      method = parts[0]
      path = parts[1]
      version = parts.size > 2 ? parts[2] : "HTTP/1.1"

      case context.prng.rand(3)
      when 0 # Query param mutation
        if path.includes?("?")
          base, query = path.split("?", 2)
          params = query.split("&").map do |param|
            if param.includes?("=")
              k, v = param.split("=", 2)
              k + "=" + context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
            else
              param
            end
          end
          path = base + "?" + params.join("&")
        else
          path = path + "?fuzz=" + context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
        end
      when 1 # Path repetition / depth
        path = path + "/../" + context.prng.rand_log(6).to_s
      else # Method case / variation
        method = context.prng.choice(["GET", "POST", "PUT", "HEAD", "OPTIONS", "PATCH"])
      end

      "#{method} #{path} #{version}"
    end

    private def mutate_headers(headers : Array(String), context : Context) : Array(String)
      return headers if headers.empty?
      new_headers = headers.dup
      idx = context.prng.rand(new_headers.size)
      line = new_headers[idx]

      if line.includes?(":")
        name, val = line.split(":", 2)
        val = val.strip
        mutated_val = case context.prng.rand(3)
                      when 0 then context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
                      when 1 then val * context.prng.rand(2..5)
                      else        "\u202E" + val
                      end
        new_headers[idx] = "#{name}: #{mutated_val}"
      end
      new_headers
    end

    private def duplicate_or_reorder_headers(headers : Array(String), context : Context) : Array(String)
      return headers if headers.empty?
      new_headers = headers.dup
      if context.prng.rand_bool
        # Duplicate random header
        h = context.prng.choice(new_headers)
        new_headers.insert(context.prng.rand(new_headers.size + 1), h)
      else
        # Shuffle order
        context.prng.shuffle!(new_headers)
      end
      new_headers
    end

    private def mutate_body(body : String, context : Context) : String
      return "fuzz_payload" if body.empty?
      case context.prng.rand(3)
      when 0 then ""                             # truncate
      when 1 then body * context.prng.rand(2..4) # expand
      else        body + "\r\n" + context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      end
    end
  end
end
