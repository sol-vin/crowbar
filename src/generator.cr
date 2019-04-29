abstract class Crowbar::Generator
  include Weighted
  
  getter length_limit : Range(Int32, Int32) = (0..10)
  getter mutator : Mutator
  getter iteration = 0

  def initialize(@mutator, @length_limit = (0..10), no_register = false)
    unless no_register
      @mutator << self
    end
  end

  private def crowbar
    mutator.selector.crowbar
  end
  
  abstract def make : String
end