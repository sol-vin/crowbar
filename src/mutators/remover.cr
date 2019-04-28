# Removes symbols
class Crowbar::Mutator::Remover < Crowbar::Mutator
  @regex : Regex = Constants::Regex::SYMBOLS
  def initialize(crowbar, @regex = Constants::Regex::SYMBOLS)
    super crowbar
  end

  def mutate(input)
    # detect symbols in text
    matches = [] of Int32
    input.scan(@regex) do |match|
      if match.begin
        matches << match.begin.as(Int32)
      end
    end

    # TODO: FIX THIS FOR MULTICHAR DELETES
    effect = self.crowbar.noise.height_float(self.crowbar.iteration, self.crowbar.iteration, 1)
    index_offset = 0
    output = input
    symbols_shuffle = self.crowbar.noise.shuffle(self.crowbar.iteration, matches)
    symbols_shuffle[0..(matches.size*effect).to_i].sort.each do |index|
      output = output.sub(index + index_offset, "")
      index_offset -= 1
    end
    output
  end
end