# # Duplicates symbols next to each other
# class Crowbar::Mutator::Repeater < Crowbar::Mutator
#   @regex : Regex = Constants::Regex::SYMBOLS
#   def initialize(crowbar, @regex = Constants::Regex::SYMBOLS)
#     super crowbar
#   end

#   def mutate(input)
#     # detect symbols in text
#     matches = input.scan(@regex)

#     #TODO: FIX THIS FOR MULTI CHAR INSERTS
#     effect = self.crowbar.noise.height_float(self.crowbar.iteration, self.crowbar.iteration, 1)
#     index_offset = 0
#     output = input
#     symbols_shuffle = self.crowbar.noise.shuffle(self.crowbar.iteration, matches)
#     symbols_shuffle[0..(matches.size*effect).to_i].sort{|a,b| a.begin.as(Int32) <=> b.begin.as(Int32)}.each do |match|
#       output = output.insert(match.begin.as(Int32) + index_offset, match[0])
#       index_offset += 1
#     end
#     output
#   end
# end