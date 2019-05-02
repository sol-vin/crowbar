class Crowbar::Selector::Header < Crowbar::Selector
  @pos = 0
  property? invert : Bool = false
  def initialize(crowbar, @size : Int32, @invert = false)
    super crowbar do |cr|
      yield cr
    end
  end

  def matches : Array(::Crowbar::Match)
    header = ::Crowbar::Match.new
    header.start = 0
    header.finish = @size
    header.string = crowbar.working_input[0..@size-1]
    header.matched = true unless invert?

    rest = ::Crowbar::Match.new
    rest.start = @size
    rest.finish = crowbar.working_input.size
    rest.string = crowbar.working_input[@size..]
    rest.matched = true if invert?
    [header, rest]
  end 
end