require "./spec_helper"
require "../src/crowbar/encoding"

describe Crowbar::Encoding do
  describe "Hex Decoding & Encoding" do
    it "decodes continuous hex strings" do
      buf = Crowbar::Encoding.decode("48656c6c6f", :hex)
      buf.to_s.should eq("Hello")
    end

    it "decodes hex with 0x prefix and spaces" do
      buf = Crowbar::Encoding.decode("0x48 0x65 0x6c 0x6c 0x6f", :hex)
      buf.to_s.should eq("Hello")
    end

    it "decodes colon and comma delimited hex" do
      buf1 = Crowbar::Encoding.decode("de:ad:be:ef", :hex)
      buf1.to_slice.should eq(Bytes[0xDE, 0xAD, 0xBE, 0xEF])

      buf2 = Crowbar::Encoding.decode("de, ad, be, ef", :hex)
      buf2.to_slice.should eq(Bytes[0xDE, 0xAD, 0xBE, 0xEF])
    end

    it "pads odd-length hex strings cleanly" do
      buf = Crowbar::Encoding.decode("f", :hex)
      buf.to_slice.should eq(Bytes[0x0F])
    end

    it "encodes buffer to lowercase continuous hex" do
      hex = Crowbar::Encoding.encode(Bytes[0xDE, 0xAD, 0xBE, 0xEF], :hex)
      hex.should eq("deadbeef")
    end
  end

  describe "C-Style Escape Decoding & Encoding" do
    it "decodes standard C-style hex and character escapes" do
      escaped = "USER \\x00\\xff\\r\\n\\t\\\"\\'\\\\"
      buf = Crowbar::Encoding.decode(escaped, :escape)
      slice = buf.to_slice
      slice[0, 5].should eq(Bytes[0x55, 0x53, 0x45, 0x52, 0x20]) # "USER "
      slice[5].should eq(0x00_u8)                                # \x00
      slice[6].should eq(0xFF_u8)                                # \xff
      slice[7].should eq(0x0D_u8)                                # \r
      slice[8].should eq(0x0A_u8)                                # \n
      slice[9].should eq(0x09_u8)                                # \t
      slice[10].should eq(0x22_u8)                               # \"
      slice[11].should eq(0x27_u8)                               # \'
      slice[12].should eq(0x5C_u8)                               # \\
    end

    it "decodes \\0 null byte escape" do
      buf = Crowbar::Encoding.decode("test\\0bin", :escape)
      buf.to_slice.should eq(Bytes[0x74, 0x65, 0x73, 0x74, 0x00, 0x62, 0x69, 0x6E])
    end

    it "encodes non-printable characters as \\xHH and control characters as escapes" do
      buf = Crowbar::Buffer.new(Bytes[0x41, 0x00, 0x0A, 0xFF])
      encoded = Crowbar::Encoding.encode(buf, :escape)
      encoded.should eq("A\\0\\n\\xff")
    end
  end

  describe "Bitstring Decoding & Encoding" do
    it "decodes bitstrings with 0b prefix and spaces" do
      buf = Crowbar::Encoding.decode("0b01000001 01000010", :bit)
      buf.to_s.should eq("AB")
    end

    it "decodes continuous unspaced bitstrings" do
      buf = Crowbar::Encoding.decode("010000010100001001000011", :bit)
      buf.to_s.should eq("ABC")
    end

    it "pads unaligned bitstrings to byte boundary" do
      buf = Crowbar::Encoding.decode("1111", :bit)
      buf.to_slice.should eq(Bytes[0x0F])
    end

    it "encodes buffer into continuous 8-bit octet strings" do
      encoded = Crowbar::Encoding.encode(Bytes[0x41, 0x42], :bit)
      encoded.should eq("0100000101000010")
    end
  end

  describe "Base64 Decoding & Encoding" do
    it "decodes base64 strings" do
      buf = Crowbar::Encoding.decode("SGVsbG8gQ3Jvd2JhciE=", :base64)
      buf.to_s.should eq("Hello Crowbar!")
    end

    it "encodes buffer to strict base64" do
      encoded = Crowbar::Encoding.encode(Bytes[0x48, 0x65, 0x6C, 0x6C, 0x6F], :base64)
      encoded.should eq("SGVsbG8=")
    end
  end

  describe "Auto-Detection Format" do
    it "detects 0x prefix as hex" do
      Crowbar::Encoding.detect("0xdeadbeef").should eq(Crowbar::Encoding::Format::Hex)
    end

    it "detects 0b prefix as bit" do
      Crowbar::Encoding.detect("0b01010100").should eq(Crowbar::Encoding::Format::Bit)
    end

    it "detects \\x escape sequences as escape" do
      Crowbar::Encoding.detect("prefix\\x00suffix").should eq(Crowbar::Encoding::Format::Escape)
    end

    it "detects hex pairs with spaces as hex" do
      Crowbar::Encoding.detect("48 65 6c 6c 6f").should eq(Crowbar::Encoding::Format::Hex)
    end

    it "falls back to raw for regular text" do
      Crowbar::Encoding.detect("Standard plain text input").should eq(Crowbar::Encoding::Format::Raw)
    end
  end
end
