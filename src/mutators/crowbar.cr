# Repeats symbols
class ::Crowbar::Mutator::Crowbar < ::Crowbar::Mutator
  @crowbar : ::Crowbar
  def initialize(selector, &block : ::Crowbar -> Nil)
    super(selector) { |m| }
    @crowbar = ::Crowbar.new &block
  end

  def mutate(match : ::Crowbar::Match) : String
    @crowbar.input = match.string
    @iteration += 1
    @crowbar.next
  end
end