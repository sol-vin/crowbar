require "perlin_noise"

require "./constants"

require "./generator"
require "./generators/*"


require "./mutator"
require "./mutators/*"

class Crowbar
  VERSION = "0.0.0.1"
  
  getter seed : Int32 = 0
  getter iteration : UInt32 = 0
  getter input : String = ""
  
  getter selectors = [] of Selector

  getter noise : PerlinNoise = PerlinNoise.new


  def initialize(@input = "", @seed = 1234)
    restart
    yield self
  end

  def << (selector : Selector)
    @selectors << selector
  end

  # Give the next test string
  def next : String
    output = input
    # Shuffle mutators, select number via range
    @noise.shuffle(@iteration, mutators)[0..@noise.int(@iteration, 0, @mutators.size)].each do |mutator|
      output = mutator.mutate(output)
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
