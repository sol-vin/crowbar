require "./crowbar"
header = "\xFF\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFC\x03\x36\x00\x00\x00"
# header = ""
# 20.times do |x|
#   header += String.new(Bytes[0x41+x])
# end
sample_input = header + "{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
cr = Crowbar.new(sample_input, seed: 1234) do |cr|
  # Type selector
  type_selector = Crowbar::Selector::Range.new(cr, (0...3)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end
  #type_selector.weight = -1.0

  # SessionID selector
  session_id_selector = Crowbar::Selector::Range.new(cr, (4...7)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end
  #session_id_selector.weight = 5.0

  # Unknown1 selector
  unknown1_selector = Crowbar::Selector::Range.new(cr, (8...11)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end
  # unknown1_selector.weight = 0.5

  # Unknown2 selector
  unknown2_selector = Crowbar::Selector::Range.new(cr, (12...13)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (2..2))
    end
  end
  # unknown2_selector.weight = 0.5

  # Magic selector
  magic_selector = Crowbar::Selector::Range.new(cr, (14...15)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (2..2))
    end
  end
  # magic_selector.weight = 0.5

  # Size selector
  size_selector = Crowbar::Selector::Range.new(cr, (16...19)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))      
    end
  end
  # size_selector.weight = 0.5

  # Message selector
  message_selector = Crowbar::Selector::Regex.new(cr, /(?<=.{20})(.+)/) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::String.new(m, strings: ["{YESYESYES!}"])
    end
  end
  message_selector.weight = 10.0
end

30.times do |x|
  pp cr.next
end
