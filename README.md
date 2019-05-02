# crowbar
*Prying your client since 2019*

![crowbar](https://github.com/redcodefinal/crowbar/raw/master/crowbar.gif "Crowbar")

Crowbar is an all-purpose fuzzer built to help make bad data cases from sample input. It can be both used as a library, and also built into an application.

## Overview
Crowbar uses selectors, mutators, and generators, to make input that potentially will make an application misbehave. In this system, selectors target and sample data, passes the data into a mutator to change it in some way, which uses generators to provide the underlying data to manipulate.

## Installation

```
shards install 
```

## Usage

### Library

Sample usage

```crystal
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
    Crowbar::Mutator::Remover.new(s) {|m|}.weight = 0.3_f32
    Crowbar::Mutator::Repeater.new(s) {|m|}.weight = 0.4_f32
  end
  # weigh the slector less so it doesn't go too wild
  s.weight = 0.7_f32

  s = Crowbar::Selector::Regex.new(cr, /[a-zA-Z0-9]{1}/) do |s|
    Crowbar::Mutator::Remover.new(s) {|m|}.weight = 0.1_f32
  end
  s.weight = 0.1_f32
end 

10.times do |x|
  pp cr.next
end
```
Sample output
```
[Running] crystal "/home/ian/Documents/crystal/crowbar/src/sandbox.cr"
"\xC1:::   : IL, NIL :  }"
"{ \"json\" : \"A String\", \"x\" : 0x123A }"
"  16.4 : \"True\", \"x\" :  "
"{ \u0001]\n" + "\xF7\xDEg : \"A String\", \"x\" : 0x123AA }"
"  \"\"json\" : \"A String\", \"x\" ::: }}}"
"   \"json\" : \"A String\", s\x99@5\xDE :  }"
"{ null : \"A String\", \"x\" : 0x123AA }"
" \"json\" : \"A String\", \"x\"\"\"  : }}}"
"{ \"false\"A String\", \"x\" : 0x123AA }"
"{ \"json\" : \"A String\",  x\"::: }""
[Done] exited with code=0 in 0.818 seconds
```
Real-world Example
```crystal
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

10.times do |x|
  pp cr.next
end
```

Output:
```
"\u0000\v\xA8\x9D\xFE\u0002\u0000\xFF\u0000\u0000\u0000\u0000\u0000\u0000\xFC\u00036\u0000\u0000\u0000{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\u0000\u0000\u0000\u0000\u0000\u0000\xFC\u00036\u0000\u0000\u0000{{True(((ݙ),:}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\u0000\u0000\u0000\u0000\u0000\u0000\xFC\u00036\u0000\u0000\u0000{'True':,:}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\u0002+\x8E\xBE\u0000\u0000\xFC\u00036\u0000\u0000\u0000{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\u0000\u0000\u0000\u0000\u0000\u0000\xFC\u00036\u0000\u0000\u0000{{12.0}:\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\xBE\xC9\xF7\xA5\u0000\u0000\xFC\u00036\u0000\u0000\u0000{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\u0000\u0000\u0000\u0000\x9Dn\xFC\u00036\u0000\u0000\u0000{\"Name\":{()},\"SessionID\":\"0x00000000\"}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\u0000\u0000\u0000\u0000\u0000\u0000\xFC\u0003\x8E\xBE\xC9\xF7{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFFTn\x82\xE9\u0000\u0000\xFC\u00036\u0000\u0000\u0000{\"Name\":\"SystemInfo\",\"SessionID\":\"0x00000000\"}"
"\xFF\u0001\u0000\xFF\xFE\u0002\u0000\xFF\u0000\u0000\u0000\u0000\xC9\xF7\xFC\u00036\u0000\u0000\u0000{\"Name\":\"275252\",\"SessionID\":\"0x00000000\"}"
```
### Application

- CLI examples

## Development

Fork it and pull request, or complain in issues idk

## Contributing

1. Fork it (<https://github.com/your-github-user/crowbar/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Ian Rash](https://github.com/redcodefinal) - creator and maintainer
