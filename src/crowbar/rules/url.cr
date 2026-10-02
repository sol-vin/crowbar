require "uri"
require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for URIs, URLs, and Query Strings.
  # Maintains standard RFC 3986 URI framing while mutating paths, queries, ports, and schemes.
  class URLRule < Rule
    def name : String
      "url"
    end

    def description : String
      "Structure-preserving URI/URL and query string mutation (valid RFC 3986 formatting)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_s.strip
      return false if str.empty?
      has_scheme = str.starts_with?("http://") || str.starts_with?("https://") ||
                   str.starts_with?("ws://") || str.starts_with?("wss://") ||
                   str.starts_with?("ftp://") || str.starts_with?("file://")
      has_query = str.includes?('?') && str.includes?('=')
      return false unless has_scheme || has_query

      URI.parse(str)
      true
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_s.strip
      uri = URI.parse(raw_str)

      case context.prng.rand(4)
      when 0
        # Mutate query parameters
        mutate_query(uri, context)
      when 1
        # Mutate path (traversal, repetitions, extensions)
        mutate_path(uri, context)
      when 2
        # Mutate port
        mutate_port(uri, context)
      else
        # Mutate scheme
        mutate_scheme(uri, context)
      end

      new_url = uri.to_s
      buffer.replace_range(0, buffer.size, new_url.to_slice)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_query(uri : URI, context : Context)
      query = uri.query
      params = if query && !query.empty?
                 URI::Params.parse(query)
               else
                 URI::Params.new
               end

      case context.prng.rand(3)
      when 0 # Add boundary query param
        params["fuzz"] = context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      when 1 # Mutate existing param value
        keys = params.empty? ? ["q"] : params.map { |k, _| k }
        k = context.prng.choice(keys)
        params[k] = context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      else # Parameter pollution / duplicate key
        keys = params.empty? ? ["id"] : params.map { |k, _| k }
        k = context.prng.choice(keys)
        params.add(k, "polluted_value")
      end

      uri.query = params.to_s
    end

    private def mutate_path(uri : URI, context : Context)
      path = uri.path.empty? ? "/" : uri.path
      new_path = case context.prng.rand(4)
                 when 0 then path + "/../" + path.lchop('/')
                 when 1 then path + "/././"
                 when 2 then path + "//" + context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
                 else        path + "%20%00%2e%2e"
                 end
      uri.path = new_path
    end

    private def mutate_port(uri : URI, context : Context)
      ports = [0, 80, 443, 8080, 8443, 65535]
      uri.port = context.prng.choice(ports)
    end

    private def mutate_scheme(uri : URI, context : Context)
      schemes = ["http", "https", "ws", "wss", "ftp", "file", "custom"]
      uri.scheme = context.prng.choice(schemes)
    end
  end
end
