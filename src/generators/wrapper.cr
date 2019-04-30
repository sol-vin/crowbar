class Crowbar::Generator::Wrapper < Crowbar::Generator
  property wraps = [["\"","\""], 
                    ["\'","\'"],
                    ["{", "}"], 
                    ["[", "]"], 
                    ["`", "`"],
                    ["(", ")"]]


  def initialize(mutator, @generator : Generator, @wraps = [["\"","\""], ["\'","\'"], ["{", "}"], ["[", "]"], ["`", "`"], ["(", ")"]])
    super mutator
  end
  
  def make : ::String
    @iteration += 1
    wrap = crowbar.noise.item(crowbar.iteration, iteration, @wraps)
    wrap[0] + @generator.make + wrap[1]
  end
end