class Crowbar::Generator::Character < Crowbar::Generator
  # TODO: Change to quote_type/wrap_type, [] {} "" '' othjer custom wraps

  def initialize(mutator, @chars = [] of Char)
    super mutator, (1..1)
  end
  
  def make : ::String
    output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, @chars)
    @iteration += 1
    output.to_s
  end
end