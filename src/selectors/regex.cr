class Crowbar::Selector::Regex < Crowbar::Selector
  @regex = /a/
  def initialize(crowbar, @regex)
    super crowbar do |cr|
      yield cr
    end
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