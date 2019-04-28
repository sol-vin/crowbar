abstract class Crowbar::Mutator
  getter selectors = [] of Selector
  getter iteration = 0

  def initialize(@selector)
    @selector << self
  end

  def << (selector : Selector)
    @selectors << selector
  end

  abstract def mutate(input : String) : String
end