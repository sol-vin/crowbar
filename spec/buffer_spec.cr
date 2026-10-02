require "./spec_helper"

describe Crowbar::Buffer do
  it "initializes from string and bytes correctly" do
    buf1 = Crowbar::Buffer.new("hello world")
    buf1.size.should eq(11)
    buf1.to_s.should eq("hello world")

    buf2 = Crowbar::Buffer.new(Bytes[1, 2, 3, 4, 5])
    buf2.size.should eq(5)
    buf2[0].should eq(1_u8)
    buf2[4].should eq(5_u8)
  end

  it "supports range indexing and slicing" do
    buf = Crowbar::Buffer.new("0123456789")
    buf[2..4].should eq(Bytes[0x32, 0x33, 0x34])
    buf[8..].should eq(Bytes[0x38, 0x39])
    buf[..2].should eq(Bytes[0x30, 0x31, 0x32])
    buf[3, 4].should eq(Bytes[0x33, 0x34, 0x35, 0x36])
  end

  it "inserts, deletes, and replaces byte ranges accurately" do
    buf = Crowbar::Buffer.new("hello world")
    buf.insert(5, "_there".to_slice)
    buf.to_s.should eq("hello_there world")

    buf.delete_range(5, 6) # delete "_there"
    buf.to_s.should eq("hello world")

    buf.replace_range(6, 5, "universe".to_slice)
    buf.to_s.should eq("hello universe")
  end

  it "identifies balanced delimiter pairs" do
    buf = Crowbar::Buffer.new("foo (bar) baz [123] \"quote\"")
    paren_pairs = buf.find_delimiter_pairs(0x28_u8, 0x29_u8) # ()
    paren_pairs.size.should eq(1)
    buf[paren_pairs[0][0]...paren_pairs[0][1]].should eq("(bar)".to_slice)

    quote_pairs = buf.find_delimiter_pairs(0x22_u8, 0x22_u8) # ""
    quote_pairs.size.should eq(1)
    buf[quote_pairs[0][0]...quote_pairs[0][1]].should eq("\"quote\"".to_slice)
  end

  it "safely handles raw binary non-UTF-8 data" do
    raw = Bytes[0xFF, 0xFE, 0x00, 0xAA, 0xBB, 0xCC, 0x80, 0x81]
    buf = Crowbar::Buffer.new(raw)
    buf.size.should eq(8)

    buf.insert(4, Bytes[0x11, 0x22])
    buf.size.should eq(10)
    buf[4].should eq(0x11_u8)
    buf[5].should eq(0x22_u8)

    # Calling to_s should not raise exceptions
    buf.to_s.should be_a(String)
  end
end
