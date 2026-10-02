require "./spec_helper"

describe "Crowbar Selectors & Combinators" do
  describe Crowbar::Selectors::DelimitedField do
    it "selects the target field in each CSV line" do
      data = "id,name,role\n1,alice,admin\n2,bob,guest\n"
      buffer = Crowbar::Buffer.new(data)
      selector = Crowbar::Selectors::DelimitedField.new(1, ',')

      ranges = selector.select(buffer)
      ranges.size.should eq(3)

      # 1st line: "name"
      String.new(buffer[ranges[0][0]...ranges[0][1]]).should eq("name")
      # 2nd line: "alice"
      String.new(buffer[ranges[1][0]...ranges[1][1]]).should eq("alice")
      # 3rd line: "bob"
      String.new(buffer[ranges[2][0]...ranges[2][1]]).should eq("bob")
    end

    it "supports negative index for last field" do
      data = "a:b:c\nd:e:f\n"
      buffer = Crowbar::Buffer.new(data)
      selector = Crowbar::Selectors::DelimitedField.new(-1, ':')

      ranges = selector.select(buffer)
      String.new(buffer[ranges[0][0]...ranges[0][1]]).should eq("c")
      String.new(buffer[ranges[1][0]...ranges[1][1]]).should eq("f")
    end

    it "respects quoted fields containing commas" do
      data = "1,\"smith, john\",30\n"
      buffer = Crowbar::Buffer.new(data)
      selector = Crowbar::Selectors::DelimitedField.new(1, ',')

      ranges = selector.select(buffer)
      String.new(buffer[ranges[0][0]...ranges[0][1]]).should eq("\"smith, john\"")
    end
  end

  describe Crowbar::Selectors::CharacterClass do
    it "isolates contiguous runs of digits" do
      buffer = Crowbar::Buffer.new("abc123def45gh6")
      selector = Crowbar::Selectors::CharacterClass.new(:digits)

      ranges = selector.select(buffer)
      extracted = ranges.map { |(s, e)| String.new(buffer[s...e]) }
      extracted.should eq(["123", "45", "6"])
    end

    it "isolates contiguous hex strings" do
      buffer = Crowbar::Buffer.new("foo 0xDEADBEEF bar")
      selector = Crowbar::Selectors::CharacterClass.new(:hex, min_length: 4)

      ranges = selector.select(buffer)
      extracted = ranges.map { |(s, e)| String.new(buffer[s...e]) }
      extracted.should contain("DEADBEEF")
    end
  end

  describe Crowbar::Selectors::Stride do
    it "selects bytes at fixed periodic intervals" do
      buffer = Crowbar::Buffer.new("0123456789")
      selector = Crowbar::Selectors::Stride.new(step: 3, offset: 1, length: 1)

      ranges = selector.select(buffer)
      extracted = ranges.map { |(s, e)| String.new(buffer[s...e]) }
      extracted.should eq(["1", "4", "7"])
    end
  end

  describe Crowbar::Selectors::Entropy do
    it "calculates high entropy for varied bytes and low for repetitive bytes" do
      rep = Bytes.new(32, 0x41_u8) # all 'A'
      low_h = Crowbar::Selectors::Entropy.calculate_entropy(rep)
      low_h.should eq(0.0)

      varied = Bytes.new(256) { |i| i.to_u8 }
      high_h = Crowbar::Selectors::Entropy.calculate_entropy(varied)
      high_h.should be_close(8.0, 0.01)
    end
  end

  describe Crowbar::Selectors::JSONKeyPath do
    it "locates the value of a specific JSON key" do
      json = "{\"user\": \"alice\", \"age\": 42, \"active\": true}"
      buffer = Crowbar::Buffer.new(json)
      selector = Crowbar::Selectors::JSONKeyPath.new("age")

      ranges = selector.select(buffer)
      ranges.size.should eq(1)
      String.new(buffer[ranges[0][0]...ranges[0][1]]).strip.should eq("42")
    end
  end

  describe Crowbar::Selectors::XMLTag do
    it "locates inner content of specific XML tag" do
      xml = "<doc><title>Hello World</title><title>Second</title></doc>"
      buffer = Crowbar::Buffer.new(xml)
      selector = Crowbar::Selectors::XMLTag.new("title")

      ranges = selector.select(buffer)
      extracted = ranges.map { |(s, e)| String.new(buffer[s...e]) }
      extracted.should eq(["Hello World", "Second"])
    end
  end

  describe "Combinator Operators (&, |, ~)" do
    it "intersects two selectors with &" do
      # Delimited field 0 has "123abc"
      # Digits character class matches "123" and "456"
      buffer = Crowbar::Buffer.new("123abc,456def\n")
      field_sel = Crowbar::Selectors::DelimitedField.new(0, ',')
      digits_sel = Crowbar::Selectors::CharacterClass.new(:digits)

      combined = field_sel & digits_sel
      ranges = combined.select(buffer)

      ranges.size.should eq(1)
      String.new(buffer[ranges[0][0]...ranges[0][1]]).should eq("123")
    end

    it "unions two selectors with |" do
      buffer = Crowbar::Buffer.new("header:BODY:footer")
      head = Crowbar::Selectors::Header.new(6)
      foot = Crowbar::Selectors::Footer.new(6)

      combined = head | foot
      ranges = combined.select(buffer)

      ranges.size.should eq(2)
      String.new(buffer[ranges[0][0]...ranges[0][1]]).should eq("header")
      String.new(buffer[ranges[1][0]...ranges[1][1]]).should eq("footer")
    end

    it "inverts a selector with ~" do
      buffer = Crowbar::Buffer.new("HEADER_REST_OF_DATA")
      head = Crowbar::Selectors::Header.new(6)
      rest = ~head

      ranges = rest.select(buffer)
      ranges.size.should eq(1)
      String.new(buffer[ranges[0][0]...ranges[0][1]]).should eq("_REST_OF_DATA")
    end
  end
end
