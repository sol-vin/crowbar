require "./crowbar"
header = "\xFF\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFC\x03\x36\x00\x00\x00"
# header = ""
# 20.times do |x|
#   header += String.new(Bytes[0x41+x])
# end
sample_input = header + "{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
cr = Crowbar.new(sample_input, seed: 1234) do |cr|
  # Type selector
  Crowbar::Selector::Range.new(cr, (0...3)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end

  # SessionID selector
  Crowbar::Selector::Range.new(cr, (4...7)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end

  # Unknown1 selector
  Crowbar::Selector::Range.new(cr, (8...11)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end

  # Unknown2 selector
  Crowbar::Selector::Range.new(cr, (12...13)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (2..2))
    end
  end

  # Magic selector
  Crowbar::Selector::Range.new(cr, (14...15)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (2..2))
    end
  end

  # Size selector
  Crowbar::Selector::Range.new(cr, (16...19)) do |s|
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))      
    end
  end

  # Message selector
  Crowbar::Selector::Regex.new(cr, /(?<=.{20})(.+)/) do |s|
    s.weight = 2.0
    message_crowbar = Crowbar.new do |cr|
      # Selects quoted strings
      Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::IN_QUOTES) do |s|
        s.weight = 10.0
        # Replace those strings with something else
        Crowbar::Mutator::Replacer.new(s) do |m|
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Decimal.new(m)).weight = 0.2
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Decimal.new(m, float: true)).weight = 0.4
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Bytes.new(m)).weight = 0.6
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Naughty.new(m, types: [:null, :logic])).weight = 0.8
        end
      end

      # Selects symbols/spaces, removes them and duplicates them
      # Crowbar::Selector::Regex.new(cr, /\W/) do |s|
      #   Crowbar::Mutator::Remover.new(s)  do |m| 
      #     m.weight = 0.01_f32
      #   end
      #   Crowbar::Mutator::Repeater.new(s)  do |m| 
      #     m.weight = 0.01_f32
      #   end
      #   s.weight = 0.02_f32
      # end
    end
    Crowbar::Mutator::Crowbar.new(s, message_crowbar) do |m|
    end
  end
end

30.times do |x|
  pp cr.next
end
