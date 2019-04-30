# Repeats symbols
class ::Crowbar::Mutator::Crowbar < ::Crowbar::Mutator
  def initialize(selector, @crowbar : ::Crowbar)
    super selector do |m|
      yield m
    end
  end

  def mutate(match : ::Crowbar::Match) : String
    @crowbar.input = match.string
    @iteration += 1
    @crowbar.next
  end
end