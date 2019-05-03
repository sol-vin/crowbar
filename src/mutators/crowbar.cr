# Repeats symbols
class ::Crowbar::Mutator::Crowbar < ::Crowbar::Mutator
  @crowbar : ::Crowbar
  def initialize(selector, @seed = 4321, &block : ::Crowbar -> Nil)
    super(selector) { |m| }
    @crowbar = ::Crowbar.new(seed: @seed, &block)
  end

  def mutate(match : ::Crowbar::Match) : String
    @crowbar.input = match.string
    @iteration += 1
    @crowbar.next
  end
end