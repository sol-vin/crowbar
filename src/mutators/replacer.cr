# Replaces symbols
class ::Crowbar::Mutator::Replacer < ::Crowbar::Mutator
  def initialize(selector)
    super selector do |m|
      yield m
    end
  end

  def mutate(match : ::Crowbar::Match) : String
    item = crowbar.noise.item(iteration, crowbar.iteration, @generators).make
    @iteration += 1
    item
  end
end