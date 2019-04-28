require "./crowbar"

cr = Crowbar.new("{ \"json\" : \"A String\", \"x\" : 0x123AA}") do |cr|
  Selector::Regex.new(cr) do |s|
    Mutator::Replacer.new(s) do |m|
      Generator::Decimals.new(m)
    end
  end

end




20.times do |x|
  puts cr.next
end
