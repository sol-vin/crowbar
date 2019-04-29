class Crowbar::Generator::String < Crowbar::Generator
  # TODO: Change to quote_type/wrap_type, [] {} "" '' othjer custom wraps
  property? quoted = false

  def initialize(mutator, @quoted = false, @strings = [] of ::String)
    super mutator, (1..1)
  end
  
  def make : ::String
    output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, @strings)
    @iteration += 1
    quoted? ? "\"" + output + "\"" : output.to_s
  end
end