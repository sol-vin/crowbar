require "perlin_noise"

require "./constants"

require "./selector"
require "./selectors/*"

require "./generator"
require "./generators/*"


require "./mutator"
require "./mutators/*"

class Crowbar
  VERSION = "0.0.0.1"
  
  getter seed : Int32 = 0
  getter iteration : UInt32 = 0
  getter input : String = ""
  
  getter selectors : Array(Selector) = [] of Selector

  getter noise : PerlinNoise = PerlinNoise.new


  def initialize(@input = "", @seed = 1234)
    restart
    yield self
  end

  def << (selector : Crowbar::Selector)
    @selectors << selector
  end

  # Give the next test string
  def next : String
    output = input
    matches = [] of Crowbar::Match
    # Shuffle mutators, select number via range
    @noise.shuffle(@iteration, selectors)[0..@noise.int(@iteration, 0, @selectors.size)].each do |selector|
      effect = noise.height_float(iteration, iteration, 1)
      shuffled_selectors = noise.shuffle(iteration, selector.select(input))
      used_selectors = shuffled_selectors[0..(shuffled_selectors.size * effect).to_i]
      used_selectors.each do |match|
        effect = noise.height_float(iteration, iteration, 1)
        shuffled_mutators = noise.shuffle(iteration, selector.mutators)
        used_mutators = shuffled_mutators[0..(selector.mutators.size * effect).to_i]
        mutated = match.match
        used_mutators.each do |mutator|
          mutated = mutator.mutate(mutated)
        end
      end
    end
    @iteration += 1
    output
  end

  # give next test string and replace input with it
  def next_as_input : String
    @input = self.next
  end

  # Restart back to beginning
  def restart
    @noise = PerlinNoise.new @seed
    @iteration = 0
  end
end
