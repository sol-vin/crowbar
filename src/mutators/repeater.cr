# Repeats symbols
class ::Crowbar::Mutator::Repeater < ::Crowbar::Mutator
  def initialize(selector, @limits = (2..3))
    super selector do |m|
      yield m
    end
  end

  def mutate(match : ::Crowbar::Match) : String
    item = match.string * crowbar.noise.int(crowbar.iteration, iteration, @limits.begin, @limits.end)
    @iteration += 1
    item
  end
end