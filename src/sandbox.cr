require "./crowbar"

cr = Crowbar.new("{ \"json\" : \"A String\", \"x\" : 0x123AA }") do |cr|
  Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::IN_QUOTES) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Decimals.new(m)
      Crowbar::Generator::Decimals.new(m, quoted: true)
      Crowbar::Generator::Decimals.new(m, float: true)
      Crowbar::Generator::Decimals.new(m, quoted: true, float: true)
      Crowbar::Generator::Decimals.new(m, quoted: true, float: true)
      Crowbar::Generator::BytesGen.new(m, quoted: true)
      Crowbar::Generator::BytesGen.new(m)
    end
  end
end

10.times do |x|
  pp cr.next
end
