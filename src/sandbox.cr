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

      Crowbar::Generator::Decimal.new(m, float: true)
      Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Decimal.new(m, float: true, no_register: true))
    end

    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m)
      Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Bytes.new(m, no_register: true))
    end

    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Naughty.new(m, types: [:null, :logic])
      Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Naughty.new(m, types: [:null, :logic], no_register: true))
    end
  end

  # Selects symbols/spaces, removes them and duplicates them
  s = Crowbar::Selector::Regex.new(cr, /\W/) do |s|
    Crowbar::Mutator::Remover.new(s) {|m|}.personal_weight = 0.1_f32
    Crowbar::Mutator::Repeater.new(s) {|m|}.personal_weight = 0.1_f32
  end
  s.personal_weight = 0.1_f32

  s = Crowbar::Selector::Regex.new(cr, /[a-zA-Z0-9]{1}/) do |s|
    Crowbar::Mutator::Remover.new(s) {|m|}.personal_weight = 0.1_f32
  end
  s.personal_weight = 0.1_f32
end 

40.times do |x|
  pp cr.next
end
