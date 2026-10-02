module Crowbar::Selectors
  # Selects XML/HTML elements or inner contents matching a specific tag name.
  class XMLTag < Selector
    getter tag : String
    getter? inner_content_only : Bool

    def initialize(@tag : String, @inner_content_only : Bool = true, weight : Float64 = 1.0)
      super(weight)
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      str = buffer.to_raw_s
      matches = [] of Tuple(Int32, Int32)

      escaped_tag = ::Regex.escape(@tag)
      # Match opening tag: <tag(\s+[^>]*)?>
      # Match closing tag: </tag\s*>
      pattern = /<#{escaped_tag}(?:\s+[^>]*)?>([\s\S]*?)<\/#{escaped_tag}\s*>/

      str.scan(pattern) do |m|
        if @inner_content_only
          if m.size > 1
            s = m.byte_begin(1)
            e = m.byte_end(1)
            matches << {s, e} if s >= 0 && e >= s
          end
        else
          s = m.byte_begin
          e = m.byte_end
          matches << {s, e} if s >= 0 && e >= s
        end
      end

      matches
    rescue ArgumentError
      [] of Tuple(Int32, Int32)
    end
  end
end
