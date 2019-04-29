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

# Make a new crowbar, send it the sample input
cr = Crowbar.new("{ \"json\" : \"A String\", \"x\" : 0x123AA }") do |cr|
  # Searches the text and splits it by regex
  Crowbar::Selector::Regex.new(cr, Crowbar::Constants::Regex::IN_QUOTES) do |s|
    # Replaces matched data from the selector
    Crowbar::Mutator::Replacer.new(s) do |m|
      # Possible generators to use for replacement data
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
```
Sample output
```
[Running] crystal "/home/ian/Documents/crystal/crowbar/src/sandbox.cr"
"{ 4.0 : \"A String\", \"\xFA\xCF\" : 0x123AA }"
"{ \"0.5\" : \"A String\", \"x\" : 0x123AA }"
"{ \"json\" : \"A String\", \"x\" : 0x123AA }"
"{ \"json\" : \"L\xB07\u001F1\a\", \"x\" : 0x123AA }"
"{ \"json\" : \"A String\", \"x\" : 0x123AA }"
"{ \"json\" : \"A String\", \"\x918\xD3|\xE3\" : 0x123AA }"
"{ \"json\" : \"A String\", \"x\" : 0x123AA }"
"{ \"json\" : 2228.0, \"x\" : 0x123AA }"
"{ \"3653\" : \"g\x8A\xE0\u000F\", \"x\" : 0x123AA }"
"{ \xC9\xF58\xF9 : \"6.53\", \"x\" : 0x123AA }"

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
