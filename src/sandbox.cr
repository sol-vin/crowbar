require "./crowbar"

cr = Crowbar.new("{ \"json\" : \"A String\", \"x\" : 0x123AA }") do |cr|
  Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::IN_QUOTES) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Decimals.new(m)
    end
  end

  Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::EACH_CHAR) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Decimals.new(m)
    end
  end
end

20.times do |x|
  puts cr.next
end
