require "perlin_noise"

require "./constants"
require "./match"

require "./selector"
require "./selectors/*"

require "./generator"
require "./generators/*"


require "./mutator"
require "./mutators/*"

class Crowbar
  VERSION = "0.0.0.1"
  
  getter seed : Int32 = 0
  getter iteration : Int32 = 0
  getter input : String = ""
  getter working_input : String = ""
  
  getter selectors : Array(Selector) = [] of Selector

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
    @working_input = @input

    noise.shuffle(@iteration, selectors)[0..noise.int(@iteration, 0, @selectors.size)].each do |selector|
      noise.shuffle(@iteration, selector.mutators)[0..noise.int(@iteration, 0, selector.mutators.size)].each do |mutator|
        # Mutate each match
        mutants = selector.matches.map_with_index do |match, index|
          if match.matched? && noise.bool(@iteration, index, 1, 2)
            string = mutator.mutate(match)
            match.string = string
          end
          match
        end

        # Join matches back together again
        if mutants.empty?
          @working_input = @input
        else
          temp = ""
          mutants.each do |match|
            temp += match.string
          end
          @working_input = temp
        end
      end
    end
    @iteration += 1
    @working_input
  end

  # give next test string and replace input with it
  def next_as_input : String
    @input = self.next
  end

  # Restart back to beginning
  def restart
    @noise = PerlinNoise.new @seed
    @working_input = @input
    @iteration = 0

    #TODO: RESET ALL MUTATORS, GENERATORS, SELECTORS!
  end
end
