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
