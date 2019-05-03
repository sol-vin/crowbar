require "perlin_noise"

require "./constants"
require "./match"

require "./weighted"

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
  property input : String = ""
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
    retry = true
    while retry
      retry = false
      @working_input = @input

      shuffled_selectors = noise.shuffle(@iteration, selectors)
      shuffled_selectors.each_with_index do |selector, index|
        if selector.current_weight > noise.height_float(@iteration, selector.iteration, index)
          shuffled_mutators = noise.shuffle(@iteration, selector.iteration, selector.mutators)
          shuffled_mutators.each do |mutator|
            # Mutate each match
            mutants = selector.matches.map_with_index do |match, index|
              if match.matched?
                if mutator.current_weight > noise.height_float(@iteration, mutator.iteration + index)
                  string = mutator.mutate(match)
                  match.string = string
                  mutator.lose
                else
                  mutator.gain
                end
              end
              match
            end

            # Join matches back together again
            if mutants.empty?
              retry = true
            else
              temp = ""
              mutants.each do |match|
                temp += match.string
              end
              @working_input = temp
            end
          end

          selector.lose
        else
          selector.gain
        end

      end
      if @working_input == @input
        retry = true
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

  def seed=(new_seed)
    @seed = new_seed
    restart
  end
end
