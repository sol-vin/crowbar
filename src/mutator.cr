abstract class ::Crowbar::Mutator
  include Weighted
  # Keeps track of parent selector
  getter selector : ::Crowbar::Selector
  # Keeps track of children generators
  getter generators = [] of ::Crowbar::Generator
  getter iteration = 0

  def initialize(@selector, no_register = false)
    unless no_register
      @selector << self
    end
    yield self
  end

  def << (generator : ::Crowbar::Generator)
    @generators << generator
  end

  private def crowbar
    selector.crowbar
  end

  abstract def mutate(match : ::Crowbar::Match) : String
end