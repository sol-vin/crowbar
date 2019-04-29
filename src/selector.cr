abstract class Crowbar::Selector
  include Weighted
  
  getter crowbar : Crowbar
  getter mutators = [] of Crowbar::Mutator

  getter iteration = 0

  def initialize(@crowbar)
    @crowbar << self
    yield self
  end
  def << (mutator)
    @mutators << mutator
  end

  abstract def matches : Array(Crowbar::Match)
end