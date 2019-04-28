abstract class Crowbar::Generator
  getter length_limit : Range(Int32, Int32) = (0..10)
  getter mutator : Mutator
  getter iteration = 0

  def initialize(@mutator, @length_limit = (0..10))
    @mutator << self
  end
  
  abstract def make : String
end