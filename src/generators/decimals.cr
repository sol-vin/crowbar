class Generator::Decimals < Generator
  def initialize(crowbar, length_limit = (0..10))
    super crowbar, length_limit
  end
  
  def make : String
    length = self.crowbar.noise.int(self.crowbar.iteration, length_limit.begin, length_limit.end)
    output = ""
    length.times do |x|
      digit_index = self.crowbar.noise.int(self.crowbar.iteration + x, @iteration, 0, 1000)
      digit = Constants::NUMBERS.to_a[digit_index % Constants::NUMBERS.size].to_s
      output += digit
    end
    @iteration += 1
    output.to_i.to_s
  end
end