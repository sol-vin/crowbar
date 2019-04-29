require "./crowbar"
sample_input = "{ \"json\" : \"A String\", \"x\" : 0x123AA }"
cr = Crowbar.new(sample_input) do |cr|
  # Selects quoted strings
  Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::IN_QUOTES) do |s|
    # Replace those strings with something else
    Crowbar::Mutator::Replacer.new(s) do |m|
      # Either a raw decimal number
      Crowbar::Generator::Decimal.new(m)
      # or one that is quoted
      Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Decimal.new(m, no_register: true))

      # Can add both at the same time, no_register keeps the Generator from registering to the mutator
      Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Decimal.new(m, float: true))
    end

    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Bytes.new(m))
    end

    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Naughty.new(m, types: [:null, :logic]))
    end
  end

  # Selects symbols/spaces, removes them and duplicates them
  s = Crowbar::Selector::Regex.new(cr, /\W/) do |s|
    Crowbar::Mutator::Remover.new(s) {|m|}.personal_weight = 0.3_f32
    Crowbar::Mutator::Repeater.new(s) {|m|}.personal_weight = 0.4_f32
  end
  # weigh the slector less so it doesn't go too wild
  s.personal_weight = 0.7_f32

  s = Crowbar::Selector::Regex.new(cr, /[a-zA-Z0-9]{1}/) do |s|
    Crowbar::Mutator::Remover.new(s) {|m|}.personal_weight = 0.1_f32
  end
  s.personal_weight = 0.1_f32
end 

10.times do |x|
  pp cr.next
end
