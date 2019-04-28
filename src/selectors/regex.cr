class Selector::Regex < Selector
  @regex : Regex
  def initialize(@regex)
  end

  def select(input) : Array(Crowbar::Match)
    matches = input.scan(@regex)

    matches.map do |m|
      match = Crowbar::Match.new
      match.start = m.begin.as(Int32)
      match.finish = m.end.as(Int32)
      match.match = m[0]
    end
  end
end