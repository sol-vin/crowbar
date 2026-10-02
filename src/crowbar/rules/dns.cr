require "./base"

module Crowbar::Rules
  # Structure-preserving rule for DNS wire-format packets (RFC 1035).
  # Parses 12-byte DNS header and question sections, maintaining valid length-prefixed
  # domain label encoding while mutating IDs, flags, query types, counts, or label bytes.
  class DNSRule < Rule
    def name : String
      "dns"
    end

    def description : String
      "Structure-preserving DNS wire packet mutation (RFC 1035 wire framing)"
    end

    def match?(buffer : Buffer) : Bool
      # Minimum DNS packet size is 12 bytes
      return false if buffer.size < 12
      # Check QDCOUNT >= 1 (most query samples have at least 1 question)
      qdcount = IO::ByteFormat::BigEndian.decode(UInt16, buffer[4, 2])
      qdcount >= 1 && qdcount <= 10
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false if buffer.size < 12

      # Parse 12-byte header
      id = IO::ByteFormat::BigEndian.decode(UInt16, buffer[0, 2])
      flags = IO::ByteFormat::BigEndian.decode(UInt16, buffer[2, 2])
      qdcount = IO::ByteFormat::BigEndian.decode(UInt16, buffer[4, 2])
      ancount = IO::ByteFormat::BigEndian.decode(UInt16, buffer[6, 2])
      nscount = IO::ByteFormat::BigEndian.decode(UInt16, buffer[8, 2])
      arcount = IO::ByteFormat::BigEndian.decode(UInt16, buffer[10, 2])

      case context.prng.rand(4)
      when 0
        # Mutate Transaction ID
        id = context.prng.next_u32.to_u16
      when 1
        # Mutate Flags (QR, Opcode, TC, RD, RA, RCODE)
        flag_mask = (1_u16 << context.prng.rand(16))
        flags ^= flag_mask
      when 2
        # Mutate Record Counts (off-by-one)
        if context.prng.rand_bool
          qdcount = (qdcount &+ (context.prng.rand_bool ? 1_u16 : 65535_u16))
        else
          ancount = (ancount &+ 1_u16)
        end
      else
        # Mutate Question QNAME / QTYPE if question section exists
        mutate_question_section(buffer, 12, context)
      end

      # Write updated header
      IO::ByteFormat::BigEndian.encode(id, buffer[0, 2])
      IO::ByteFormat::BigEndian.encode(flags, buffer[2, 2])
      IO::ByteFormat::BigEndian.encode(qdcount, buffer[4, 2])
      IO::ByteFormat::BigEndian.encode(ancount, buffer[6, 2])
      IO::ByteFormat::BigEndian.encode(nscount, buffer[8, 2])
      IO::ByteFormat::BigEndian.encode(arcount, buffer[10, 2])

      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_question_section(buffer : Buffer, offset : Int32, context : Context)
      return if offset >= buffer.size
      pos = offset

      # Walk labels until null byte (0x00) or end
      label_positions = [] of Tuple(Int32, Int32)
      while pos < buffer.size
        len = buffer[pos].to_i32
        break if len == 0 || (len & 0xC0) == 0xC0 # End or compression pointer
        label_start = pos + 1
        label_end = label_start + len
        break if label_end > buffer.size
        label_positions << {label_start, label_end}
        pos = label_end
      end

      return if label_positions.empty?

      # Mutate a random label or QTYPE
      if context.prng.rand_bool && pos + 4 <= buffer.size
        # Mutate QTYPE (2 bytes after null terminator)
        qtype_pos = pos + 1
        weird_types = [1_u16, 28_u16, 255_u16, 0_u16, 65535_u16, 15_u16, 16_u16] # A, AAAA, ANY, 0, MAX, MX, TXT
        new_type = context.prng.choice(weird_types)
        IO::ByteFormat::BigEndian.encode(new_type, buffer[qtype_pos, 2])
      else
        # Mutate label bytes
        s, e = context.prng.choice(label_positions)
        sub_len = e - s
        if sub_len > 0
          mutate_idx = s + context.prng.rand(sub_len)
          buffer[mutate_idx] = context.prng.rand(256).to_u8
        end
      end
    end
  end
end
