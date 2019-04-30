class Crowbar::Selector::Range < Crowbar::Selector
  @range : ::Range(Int32, Int32) = (0..1)
  @pos = 0
  def initialize(crowbar, @range)
    super crowbar do |cr|
      yield cr
    end
  end

  def matches : Array(Crowbar::Match)
    matches = [] of Crowbar::Match
    if @range.begin == 0 && @range.end == crowbar.input.size-1
      m1 = Crowbar::Match.new
      m1.start = @range.begin
      m1.finish = @range.end
      m1.matched = true
      m1.string = crowbar.working_input[m1.range]
      matches << m1
    elsif @range.begin == 0
      m1 = Crowbar::Match.new
      m1.start = @range.begin
      m1.finish = @range.end
      m1.matched = true
      m1.string = crowbar.working_input[m1.range]
      matches << m1

      m2 = Crowbar::Match.new
      m2.start = @range.end+1
      m2.finish = crowbar.working_input.size
      m2.matched = false
      m2.string = crowbar.working_input[m2.range]
      matches << m2
    elsif @range.end == crowbar.working_input.size
      m1 = Crowbar::Match.new
      m1.start = 0
      m1.finish = @range.begin
      m1.matched = false
      m1.string = crowbar.working_input[m1.range]
      matches << m1

      m2 = Crowbar::Match.new
      m2.start = @range.begin
      m2.finish = @range.end
      m2.matched = true
      m2.string = crowbar.working_input[m2.range]
      matches << m2
    else
      m1 = Crowbar::Match.new
      m1.start = 0
      m1.finish = @range.begin-1
      m1.matched = false
      m1.string = crowbar.working_input[m1.range]
      matches << m1

      m2 = Crowbar::Match.new
      m2.start = @range.begin
      m2.finish = @range.end
      m2.matched = true
      m2.string = crowbar.working_input[m2.range]
      matches << m2

      m3 = Crowbar::Match.new
      m3.start = @range.end+1
      m3.finish = crowbar.working_input.size
      m3.matched = false
      m3.string = crowbar.working_input[m3.range]
      matches << m3
    end
    @iteration += 1
    matches
  end 
end