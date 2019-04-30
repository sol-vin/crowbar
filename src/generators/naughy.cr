class Crowbar::Generator::Naughty < Crowbar::Generator
  def initialize(mutator, @types = [:null, :logic, :numbers, :symbols, :empty], no_register = false)
    super mutator, no_register: no_register
  end
  
  def make : ::String
    type = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, @types)
    output = ""
    if type == :null
      output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, ::Crowbar::Constants::Naughty::NULL)
    elsif type == :logic
      output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, ::Crowbar::Constants::Naughty::LOGIC)
    elsif type == :operations
      output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, ::Crowbar::Constants::Naughty::OPERATIONS)
    elsif type == :code
      output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, ::Crowbar::Constants::Naughty::CODE)
    elsif type == :numbers
      output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, ::Crowbar::Constants::Naughty::NUMBERS)
    elsif type == :symbols
      output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, ::Crowbar::Constants::Naughty::SYMBOLS)
    elsif type == :empty
      output = self.crowbar.noise.item(self.crowbar.iteration, self.iteration, ::Crowbar::Constants::Naughty::EMPTY)
    end
    @iteration += 1
    output.to_s
  end
end