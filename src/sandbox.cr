require "./crowbar"
header = "\xFF\x01\x00\xFF\xFE\x02\x00\xFF\x00\x00\x00\x00\x00\x00\xFC\x03\x36\x00\x00\x00"
sample_input = header + "{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"

cr = Crowbar.new(sample_input, seed: (:xiongmai.hash%Int32::MAX).to_i32) do |cr|
  # Type selector
  Crowbar::Selector::Range.new(cr, (0...3)) do |s|
    s.weight = 0.01
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end

  # SessionID selector
  Crowbar::Selector::Range.new(cr, (4...7)) do |s|
    s.weight = 0.01
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end

  # Unknown1 selector
  Crowbar::Selector::Range.new(cr, (8...11)) do |s|
    s.weight = 2.0
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))
    end
  end

  # Unknown2 selector
  Crowbar::Selector::Range.new(cr, (12...13)) do |s|
    s.weight = 2.0
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (2..2))
    end
  end

  # Magic selector
  Crowbar::Selector::Range.new(cr, (14...15)) do |s|
    s.weight = 0.1
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (2..2))
    end
  end

  # Size selector
  Crowbar::Selector::Range.new(cr, (16...19)) do |s|
    s.weight = 3.0
    Crowbar::Mutator::Replacer.new(s) do |m|
      Crowbar::Generator::Bytes.new(m, length_limit: (4..4))      
    end
  end

  # Message selector
  Crowbar::Selector::Header.new(cr, 20, invert: true) do |s|
    s.weight = 10.0
    Crowbar::Mutator::Crowbar.new(s) do |cr|
      cr.input = "{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
      cr.seed = (:new_crowbar.hash%Int32::MAX).to_i32
      # Selects quoted strings
      Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::IN_QUOTES) do |s|
        s.weight = 1.0
        # Replace those strings with something else
        Crowbar::Mutator::Replacer.new(s) do |m|
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Decimal.new(m))
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Decimal.new(m, float: true))
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Bytes.new(m))
          Crowbar::Generator::Wrapper.new(m, Crowbar::Generator::Naughty.new(m, types: [:null, :logic, :empty]))
        end

        Crowbar::Mutator::Remover.new(s) do |m|
          m.weight = 0.01
        end
      end

      # Mess with symbols
      Crowbar::Selector::Regex.new(cr, /\W/) do |s|
        Crowbar::Mutator::Remover.new(s) do |m|
          m.weight = 0.01
        end

        Crowbar::Mutator::Repeater.new(s) do |m|
          m.weight = 0.01
        end
      end
    end
  end
end

100.times do |x|
  pp cr.next
end
