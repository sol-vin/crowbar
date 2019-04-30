class Crowbar::Generator::String < Crowbar::Generator
  def initialize(mutator, @strings = [] of ::String)
    super mutator, (1..1)
  end
  
  def make : ::String
    output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, @strings)
    @iteration += 1
    output
  end
end