class Crowbar::Generator::Decimals < Crowbar::Generator
  property? quoted = false
  property? float = false
  def initialize(mutator, length_limit = (0..10))
    super mutator, length_limit
  end
  
  def make : String
    length = self.crowbar.noise.int(self.crowbar.iteration, self.length_limit.begin, self.length_limit.end)
    output = ""
    point = self.crowbar.noise.int(self.crowbar.iteration, iteration, 0, length-1)
    length.times do |x|
      digit_index = self.crowbar.noise.int(self.crowbar.iteration + x, self.iteration, 0, 1000)
      digit = Crowbar::Constants::NUMBERS.to_a[digit_index % Crowbar::Constants::NUMBERS.size].to_s
      output += digit
      if float? && x == point
        output += '.'
      end
    end
    @iteration += 1
    quoted? ? "\"" + output.to_i.to_s + "\"" : output.to_i.to_s
  end
end