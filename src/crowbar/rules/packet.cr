require "./base"

module Crowbar::Rules
  # Structure-preserving rule for raw network packets (IPv4, TCP, UDP) and PCAP capture traces.
  # Automatically maintains RFC 791 16-bit Internet Header Checksums, Total Length,
  # and UDP length fields, while fuzzing ports, sequence numbers, TCP flags, TTL,
  # fragmentation offsets, IP options, and transport payloads.
  class PacketRule < Rule
    PCAP_MAGIC_LE = Bytes[0xD4, 0xC3, 0xB2, 0xA1] # 0xa1b2c3d4 Little Endian
    PCAP_MAGIC_BE = Bytes[0xA1, 0xB2, 0xC3, 0xD4] # 0xa1b2c3d4 Big Endian

    def name : String
      "packet"
    end

    def description : String
      "Structure-preserving raw IPv4, TCP, UDP, and PCAP capture framing with RFC checksum fixups"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 20

      # Check PCAP capture header
      if buffer.size >= 24
        magic = buffer[0, 4].to_slice
        if magic == PCAP_MAGIC_LE || magic == PCAP_MAGIC_BE
          return true
        end
      end

      # Check raw IPv4 packet header: Version == 4 (high nibble of byte 0) and IHL >= 5 (low nibble)
      b0 = buffer[0]
      version = (b0 >> 4) & 0x0F
      ihl = b0 & 0x0F
      return true if version == 4 && ihl >= 5

      false
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      # Handle PCAP captures vs raw packets
      if is_pcap?(buffer)
        apply_pcap(context, buffer)
      else
        apply_ipv4(context, buffer, 0)
      end
    rescue
      false
    end

    private def is_pcap?(buffer : Buffer) : Bool
      return false if buffer.size < 24
      magic = buffer[0, 4].to_slice
      magic == PCAP_MAGIC_LE || magic == PCAP_MAGIC_BE
    end

    private def apply_pcap(context : Context, buffer : Buffer) : Bool
      # PCAP has 24-byte global header, followed by packet records
      # Record: 16 bytes (ts_sec, ts_usec, incl_len, orig_len) + packet data
      pos = 24
      if pos + 16 <= buffer.size
        incl_len = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[pos + 8, 4].to_slice).to_i32 rescue 0
        pkt_offset = pos + 16
        if incl_len > 0 && pkt_offset + incl_len <= buffer.size
          # If linktype is ethernet (1), skip 14-byte MAC header if IPv4 packet follows
          ip_offset = pkt_offset
          if incl_len > 14 && (buffer[pkt_offset + 12] == 0x08_u8 && buffer[pkt_offset + 13] == 0x00_u8)
            ip_offset = pkt_offset + 14
          end

          if ip_offset + 20 <= buffer.size && ((buffer[ip_offset] >> 4) & 0x0F) == 4
            apply_ipv4(context, buffer, ip_offset)
            context.record_mutation(name)
            return true
          end
        end
      end

      # Fallback: mutate PCAP global header snaplen (bytes 16..19)
      IO::ByteFormat::LittleEndian.encode(context.prng.choice([0_u32, 65535_u32, 262144_u32]), buffer[16, 4])
      context.record_mutation(name)
      true
    end

    private def apply_ipv4(context : Context, buffer : Buffer, base_off : Int32) : Bool
      return false if buffer.size < base_off + 20

      ihl = (buffer[base_off] & 0x0F).to_i32 * 4
      return false if ihl < 20 || base_off + ihl > buffer.size

      proto = buffer[base_off + 9] # 6 = TCP, 17 = UDP, 1 = ICMP
      action = context.prng.rand(6)
      mutated = false

      case action
      when 0
        # Mutate IPv4 TTL (byte 8)
        buffer[base_off + 8] = context.prng.choice([0_u8, 1_u8, 2_u8, 64_u8, 128_u8, 255_u8])
        mutated = true
      when 1
        # Mutate IP flags and fragment offset (bytes 6..7)
        # Bit 15: Reserved/Evil bit, Bit 14: DF (Don't Fragment), Bit 13: MF (More Fragments)
        flags = [0x8000_u16, 0x4000_u16, 0x2000_u16, 0x2001_u16, 0x21FF_u16, 0x0000_u16]
        IO::ByteFormat::BigEndian.encode(context.prng.choice(flags), buffer[base_off + 6, 2])
        mutated = true
      when 2
        # Mutate Source or Destination IP (bytes 12..19)
        ips = [
          Bytes[127, 0, 0, 1],       # Loopback
          Bytes[0, 0, 0, 0],         # Any / Zero
          Bytes[255, 255, 255, 255], # Broadcast
          Bytes[224, 0, 0, 1],       # Multicast
          Bytes[169, 254, 1, 1],     # Link-local APIPA
          Bytes[10, 0, 0, 1],        # Private A
        ]
        target_off = base_off + (context.prng.rand_bool ? 12 : 16)
        buffer.replace_range(target_off, 4, context.prng.choice(ips))
        mutated = true
      when 3
        # Transport layer mutation: TCP or UDP
        if proto == 6_u8 && base_off + ihl + 20 <= buffer.size
          # TCP Header mutation
          tcp_off = base_off + ihl
          case context.prng.rand(4)
          when 0
            # Mutate TCP flags (byte 13)
            # SYN=0x02, ACK=0x10, FIN=0x01, RST=0x04, PSH=0x08, URG=0x20, SYN+FIN=0x03, NULL=0x00, XMAS=0x29
            tcp_flags = [0x02_u8, 0x12_u8, 0x04_u8, 0x01_u8, 0x03_u8, 0x29_u8, 0x00_u8, 0xFF_u8]
            buffer[tcp_off + 13] = context.prng.choice(tcp_flags)
            mutated = true
          when 1
            # Mutate TCP Window Size (bytes 14..15)
            IO::ByteFormat::BigEndian.encode(context.prng.choice([0_u16, 1_u16, 65535_u16, 1460_u16]), buffer[tcp_off + 14, 2])
            mutated = true
          when 2
            # Mutate Destination Port (bytes 2..3)
            IO::ByteFormat::BigEndian.encode(context.prng.choice([21_u16, 22_u16, 53_u16, 80_u16, 443_u16, 8080_u16, 0_u16, 65535_u16]), buffer[tcp_off + 2, 2])
            mutated = true
          else
            # Mutate TCP Sequence or Acknowledgment Number
            off = tcp_off + (context.prng.rand_bool ? 4 : 8)
            IO::ByteFormat::BigEndian.encode(context.prng.choice([0_u32, 1_u32, UInt32::MAX, context.prng.next_u64.to_u32]), buffer[off, 4])
            mutated = true
          end
        elsif proto == 17_u8 && base_off + ihl + 8 <= buffer.size
          # UDP Header mutation
          udp_off = base_off + ihl
          # Mutate destination port (bytes 2..3)
          IO::ByteFormat::BigEndian.encode(context.prng.choice([53_u16, 67_u16, 68_u16, 123_u16, 161_u16, 500_u16, 0_u16, 65535_u16]), buffer[udp_off + 2, 2])
          mutated = true
        else
          # Protocol byte mutation
          buffer[base_off + 9] = context.prng.choice([1_u8, 6_u8, 17_u8, 47_u8, 50_u8, 255_u8])
          mutated = true
        end
      when 4
        # Mutate transport payload after IP/transport header
        payload_start = base_off + ihl + (proto == 6_u8 ? 20 : (proto == 17_u8 ? 8 : 0))
        if buffer.size > payload_start
          payload_len = buffer.size - payload_start
          pos = payload_start + context.prng.rand(payload_len)
          span = Math.min(context.prng.rand(1..16), buffer.size - pos)
          span.times do |off|
            buffer[pos + off] ^= context.prng.rand(1..255).to_u8
          end
          mutated = true
        else
          # Mutate Identification (bytes 4..5)
          IO::ByteFormat::BigEndian.encode(context.prng.next_u64.to_u16, buffer[base_off + 4, 2])
          mutated = true
        end
      else
        # Mutate Identification (bytes 4..5)
        IO::ByteFormat::BigEndian.encode(context.prng.next_u64.to_u16, buffer[base_off + 4, 2])
        mutated = true
      end

      # Recalculate IPv4 Total Length (bytes 2..3)
      pkt_len = (buffer.size - base_off).to_u16
      IO::ByteFormat::BigEndian.encode(pkt_len, buffer[base_off + 2, 2])

      # Recalculate UDP length if protocol is UDP
      if proto == 17_u8 && base_off + ihl + 8 <= buffer.size
        udp_len = (buffer.size - (base_off + ihl)).to_u16
        IO::ByteFormat::BigEndian.encode(udp_len, buffer[base_off + ihl + 4, 2])
      end

      # Recalculate RFC 791 16-bit Internet Header Checksum (bytes 10..11)
      recalculate_ip_checksum(buffer, base_off, ihl)

      if mutated
        context.record_mutation(name)
        true
      else
        false
      end
    end

    def recalculate_ip_checksum(buffer : Buffer, base_off : Int32, ihl : Int32)
      # Zero out checksum field (bytes 10..11)
      buffer[base_off + 10] = 0x00_u8
      buffer[base_off + 11] = 0x00_u8

      sum = 0_u32
      i = 0
      while i < ihl
        word = IO::ByteFormat::BigEndian.decode(UInt16, buffer[base_off + i, 2].to_slice)
        sum += word.to_u32
        i += 2
      end

      # Fold 32-bit carries into 16-bit
      while (sum >> 16) > 0
        sum = (sum & 0xFFFF_u32) + (sum >> 16)
      end

      checksum = (~sum & 0xFFFF_u32).to_u16
      IO::ByteFormat::BigEndian.encode(checksum, buffer[base_off + 10, 2])
    end
  end
end
