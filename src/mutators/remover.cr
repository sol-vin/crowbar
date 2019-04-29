# Replaces symbols
class Crowbar::Mutator::Remover < Crowbar::Mutator
  def initialize(selector)
    super selector do |m|
      yield m
    end
  end

  def mutate(match : Crowbar::Match) : String
    @iteration += 1
    ""
  end
end