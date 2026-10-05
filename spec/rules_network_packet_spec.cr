require "./spec_helper"
require "../src/crowbar/rules/packet"

describe Crowbar::Rules::PacketRule do
  describe "Raw IPv4 Packet Framing & RFC 791 Checksum" do
    it "matches IPv4 packet, preserves framing, and recalculates 16-bit header checksum" do
      # 20-byte IPv4 header + 8-byte UDP header + 4 bytes payload
      total_size = 32
      pkt = Bytes.new(total_size, 0_u8)
      pkt[0] = 0x45_u8                                               # IPv4, IHL=5 (20 bytes)
      pkt[1] = 0x00_u8                                               # DSCP/ECN
      IO::ByteFormat::BigEndian.encode(total_size.to_u16, pkt[2, 2]) # Total Length
      IO::ByteFormat::BigEndian.encode(12345_u16, pkt[4, 2])         # ID
      IO::ByteFormat::BigEndian.encode(0x4000_u16, pkt[6, 2])        # Flags: Don't Fragment
      pkt[8] = 64_u8                                                 # TTL
      pkt[9] = 17_u8                                                 # Protocol: UDP (17)
      # Source IP: 192.168.1.100
      Bytes[192, 168, 1, 100].copy_to(pkt[12, 4])
      # Dest IP: 8.8.8.8
      Bytes[8, 8, 8, 8].copy_to(pkt[16, 4])

      # UDP header at offset 20: src=12345, dst=53, len=12, chksum=0
      IO::ByteFormat::BigEndian.encode(12345_u16, pkt[20, 2])
      IO::ByteFormat::BigEndian.encode(53_u16, pkt[22, 2])
      IO::ByteFormat::BigEndian.encode(12_u16, pkt[24, 2])

      buf = Crowbar::Buffer.new(pkt)
      rule = Crowbar::Rules::PacketRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(42_u64)
      applied = rule.apply(ctx, buf)
      applied.should be_true

      # Verify IPv4 version preserved
      ((buf[0] >> 4) & 0x0F).should eq(4)
      (buf[0] & 0x0F).should eq(5)

      # Verify Total Length is synchronized to buffer size
      actual_len = IO::ByteFormat::BigEndian.decode(UInt16, buf[2, 2].to_slice)
      actual_len.should eq(buf.size)

      # Verify RFC 791 16-bit Internet Header Checksum:
      # Summing all 16-bit words of the 20-byte IP header including the checksum must fold to 0xFFFF
      sum = 0_u32
      (0...20).step(2) do |i|
        word = IO::ByteFormat::BigEndian.decode(UInt16, buf[i, 2].to_slice)
        sum += word.to_u32
      end
      while (sum >> 16) > 0
        sum = (sum & 0xFFFF_u32) + (sum >> 16)
      end
      sum.should eq(0xFFFF_u32)
    end
  end

  describe "PCAP Capture Trace Framing" do
    it "matches PCAP file and mutates packet within capture framing" do
      # 24-byte PCAP global header
      pcap = Bytes.new(24 + 16 + 28, 0_u8)
      # Magic 0xa1b2c3d4 (Little Endian: d4 c3 b2 a1)
      Bytes[0xD4, 0xC3, 0xB2, 0xA1].copy_to(pcap[0, 4])
      IO::ByteFormat::LittleEndian.encode(2_u16, pcap[4, 2])      # version major 2
      IO::ByteFormat::LittleEndian.encode(4_u16, pcap[6, 2])      # version minor 4
      IO::ByteFormat::LittleEndian.encode(65535_u32, pcap[16, 4]) # snaplen
      IO::ByteFormat::LittleEndian.encode(101_u32, pcap[20, 4])   # linktype raw IP (101)

      # Record header at offset 24 (16 bytes): ts_sec, ts_usec, incl_len=28, orig_len=28
      IO::ByteFormat::LittleEndian.encode(1700000000_u32, pcap[24, 4])
      IO::ByteFormat::LittleEndian.encode(28_u32, pcap[32, 4])
      IO::ByteFormat::LittleEndian.encode(28_u32, pcap[36, 4])

      # Raw IPv4 packet at offset 40 (28 bytes: 20 bytes IP + 8 bytes UDP)
      pcap[40] = 0x45_u8
      IO::ByteFormat::BigEndian.encode(28_u16, pcap[42, 2])
      pcap[48] = 64_u8 # TTL
      pcap[49] = 17_u8 # UDP
      Bytes[10, 0, 0, 1].copy_to(pcap[52, 4])
      Bytes[10, 0, 0, 2].copy_to(pcap[56, 4])

      buf = Crowbar::Buffer.new(pcap)
      rule = Crowbar::Rules::PacketRule.new
      rule.match?(buf).should be_true

      ctx = Crowbar::Context.new(888_u64)
      applied = rule.apply(ctx, buf)
      applied.should be_true

      # Verify PCAP magic preserved
      buf[0, 4].to_slice.should eq(Bytes[0xD4, 0xC3, 0xB2, 0xA1])
    end
  end
end
