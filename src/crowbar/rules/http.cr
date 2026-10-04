require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for HTTP/1.x messages.
  # Parses Start Line, Headers, and Body, maintaining proper CRLF line framing
  # while mutating paths, query parameters, header values, or body content.
  class HTTPRule < Rule
    property? sync_content_length : Bool = true
    property targets : Array(Symbol) = [:start_line, :headers, :reorder, :body]
    property body_rule : Rule? = nil

    def initialize(@weight : Float64 = 1.0, @sync_content_length : Bool = true)
      super(@weight)
    end

    def name : String
      "http"
    end

    def description : String
      "Structure-preserving HTTP/1.x message mutation (valid framing with mutated headers/body)"
    end

    def targets(*targets : Symbol)
      @targets = targets.to_a
    end

    def body_rule(rule : Rule)
      @body_rule = rule
    end

    def body_rule(format : Symbol)
      @body_rule = case format
                   when :json then JSONRule.new
                   when :xml  then XMLRule.new
                   when :yaml then YAMLRule.new
                   when :csv  then CSVRule.new
                   else            nil
                   end
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_raw_s
      str.starts_with?("GET ") || str.starts_with?("POST ") ||
        str.starts_with?("PUT ") || str.starts_with?("DELETE ") ||
        str.starts_with?("HEAD ") || str.starts_with?("OPTIONS ") ||
        str.starts_with?("PATCH ") || str.starts_with?("HTTP/1.")
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

      available_targets = @targets.empty? ? [:start_line, :headers, :reorder, :body] : @targets
      action = context.prng.choice(available_targets)

      case action
      when :start_line
        # Mutate Start Line (Path / Query string / Method)
        start_line = mutate_start_line(start_line, context)
      when :headers
        # Mutate Header Values
        headers = mutate_headers(headers, context)
      when :reorder
        # Duplicate or reorder headers
        headers = duplicate_or_reorder_headers(headers, context)
      when :body
        # Mutate Body
        body_section = mutate_body(body_section, context)
      end

      # Strict protocol adherence: auto-synchronize Content-Length if present
      if @sync_content_length
        headers = sync_content_length_header(headers, body_section.bytesize)
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
      if reconstructed == buffer.to_slice
        headers << "X-Fuzz: #{context.prng.rand_log(8)}"
        io = IO::Memory.new
        io << start_line << "\r\n"
        headers.each do |h|
          io << h << "\r\n"
        end
        io << "\r\n"
        io << body_section
        reconstructed = io.to_slice
      end

      buffer.replace_range(0, buffer.size, reconstructed)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def sync_content_length_header(headers : Array(String), body_size : Int32) : Array(String)
      headers.map do |h|
        if h =~ /^content-length\s*:/i
          "Content-Length: #{body_size}"
        else
          h
        end
      end
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
        methods = ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"].reject { |m| m == method }
        method = methods.empty? ? "POST" : context.prng.choice(methods)
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
                      when 1 then val.empty? ? "fuzz" : val * context.prng.rand(2..5)
                      else        "\u202E" + val
                      end
        new_headers[idx] = "#{name}: #{mutated_val}"
      end
      new_headers
    end

    private def duplicate_or_reorder_headers(headers : Array(String), context : Context) : Array(String)
      return headers if headers.empty?
      new_headers = headers.dup
      if new_headers.size <= 1 || context.prng.rand_bool
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
      if rule = @body_rule
        buf = Buffer.new(body)
        if rule.match?(buf) && rule.apply(context, buf)
          return buf.to_s
        end
      end

      return "fuzz_payload" if body.empty?
      case context.prng.rand(3)
      when 0 then ""                             # truncate
      when 1 then body * context.prng.rand(2..4) # expand
      else        body + "\r\n" + context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      end
    end
  end
end
