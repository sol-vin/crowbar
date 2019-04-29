class Crowbar::Generator::Wrapper < Crowbar::Generator
  # TODO: Change to quote_type/wrap_type, [] {} "" '' othjer custom wraps
  property start = "\""
  property finish = "\""


  def initialize(mutator, @generator : Generator, @types = [:null, :logic, :numbers, :symbols, :empty])
    super mutator
  end
  
  def make : ::String
    @iteration += 1
    start + @generator.make + finish
  end
end