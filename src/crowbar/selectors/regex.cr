module Crowbar::Selectors
  # Selects regions matching a regular expression (with capture group support)
  class Regex < Selector
    getter pattern : ::Regex
    getter group : Int32

    def initialize(@pattern : ::Regex, @group : Int32 = 0, weight : Float64 = 1.0)
      super(weight)
    end

    def select(buffer : Buffer) : Array(Tuple(Int32, Int32))
      str = buffer.to_raw_s
      matches = [] of Tuple(Int32, Int32)

      str.scan(@pattern) do |match|
        if @group == 0
          b = match.byte_begin
          e = match.byte_end
          matches << {b, e}
        elsif match.size > @group
          b = match.byte_begin(@group)
          e = match.byte_end(@group)
          matches << {b, e} if b >= 0 && e >= b
        end
      end
      matches
    rescue ArgumentError
      [] of Tuple(Int32, Int32)
    end
  end
end
