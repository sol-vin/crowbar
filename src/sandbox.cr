require "./crowbar"

cr = Crowbar.new("{ \"json\" : \"A String\", \"x\" : 0x123AA }") do |cr|
  Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::IN_QUOTES) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Decimal.new(m)
      Crowbar::Generator::Decimal.new(m, quoted: true)
      Crowbar::Generator::Decimal.new(m, float: true)
      Crowbar::Generator::Decimal.new(m, quoted: true, float: true)
      Crowbar::Generator::Decimal.new(m, quoted: true, float: true)
      Crowbar::Generator::Bytes.new(m, quoted: true)
      Crowbar::Generator::Bytes.new(m)
    end
  end

  Crowbar::Selector::Regex.new(cr, /json/) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::String.new(m, strings: ["BADJSON"])
    end
  end
end

40.times do |x|
  pp cr.next
end
