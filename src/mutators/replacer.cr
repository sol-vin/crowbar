# Replaces symbols
class Crowbar::Mutator::Replacer < Crowbar::Mutator
  def initialize(selector)
    super selector do |m|
      yield m
    end
  end

  def mutate(match : Crowbar::Match) : String
    if @generators.size >= 2
      item = crowbar.noise.item(iteration, crowbar.iteration, @generators).make
    else
      item = @generators[0].make
    end
    @iteration += 1
    item
  end
end