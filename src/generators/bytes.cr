class Crowbar::Generator::Bytes < Crowbar::Generator
  def initialize(mutator, length_limit = (2..6), no_register = false)
    super mutator, length_limit, no_register: no_register
  end
  
  def make(input : ::String = "") : ::String
    length = self.crowbar.noise.int(self.crowbar.iteration, self.iteration, self.length_limit.begin, self.length_limit.end)
    output = ""
    length.times do |x|
      byte = self.crowbar.noise.int(self.crowbar.iteration + x + self.iteration, 0, 256)
      output += ::String.new(::Bytes[byte.to_u8])
      @iteration += 1
    end
    output
  end
end