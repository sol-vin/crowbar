abstract class Crowbar::Selector
  getter crowbar : Crowbar
  getter mutators = [] of Mutator

  getter iteration = 0

  def initialize(@crowbar)
    @crowbar << self
  end

  def << (mutator)
    @mutators << mutator
  end

  abstract def select(input) : Array(Crowbar::Match)
end