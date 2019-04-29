class Crowbar::Generator::Bytes < Crowbar::Generator
  property? quoted = false

  def initialize(mutator, length_limit = (2..6), @quoted = false)
    super mutator, length_limit
  end
  
  def make : ::String
    length = self.crowbar.noise.int(self.crowbar.iteration, self.length_limit.begin, self.length_limit.end)
    output = ""
    length.times do |x|
      byte = self.crowbar.noise.int(self.crowbar.iteration + x, self.iteration, 0, 256)
      output += ::String.new(::Bytes[byte.to_u8])
    end
    @iteration += 1
    quoted? ? "\"" + output + "\"" : output
  end
end