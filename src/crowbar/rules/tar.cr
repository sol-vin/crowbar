require "./base"

module Crowbar::Rules
  # Structure-preserving rule for Unix TAR archives (POSIX UStar).
  # Preserves 512-byte block alignment and UStar header structure,
  # while mutating file names, permissions, file size records, type flags,
  # or data payloads, and automatically recalculating the octal header checksum.
  class TarRule < Rule
    USTAR_MAGIC = "ustar".to_slice

    def name : String
      "tar"
    end

    def description : String
      "Structure-preserving POSIX UStar TAR archive framing with automated octal checksum fixup"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 512
      # Check for "ustar" at offset 257
      buffer[257, 5].to_slice == USTAR_MAGIC
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      action = context.prng.rand(5)
      mutated = false

      case action
      when 0
        # Mutate filename (offset 0..99)
        probes = [
          "../../../../../../../../etc/passwd",
          "..\\..\\..\\..\\Windows\\System32\\calc.exe",
          "test_file_\0_hidden.txt",
          "A" * 98,
          "/dev/null",
          "con.txt",
        ]
        chosen = context.prng.choice(probes)
        slice = chosen.to_slice
        len = Math.min(slice.size, 99)
        buffer.replace_range(0, len, slice[0, len])
        buffer[len] = 0x00_u8
        mutated = true
      when 1
        # Mutate file size (offset 124..135, 12 bytes octal e.g. "00000000010\0")
        sizes = [
          0_u64,
          1_u64,
          (buffer.size > 512 ? (buffer.size - 512).to_u64 : 0_u64),
          65535_u64,
          2147483647_u64,
          8589934591_u64, # 077777777777 octal
        ]
        chosen = context.prng.choice(sizes)
        oct_str = sprintf("%011o\0", chosen)
        buffer.replace_range(124, 12, oct_str.to_slice)
        mutated = true
      when 2
        # Mutate file mode / permissions (offset 100..107, 8 bytes octal e.g. "0000644\0")
        modes = [
          "0000777\0", # World-writable/executable
          "0004755\0", # SUID executable
          "0002755\0", # SGID executable
          "0000000\0", # No permissions
          "0007777\0", # All special bits set
        ]
        chosen = context.prng.choice(modes)
        buffer.replace_range(100, 8, chosen.to_slice)
        mutated = true
      when 3
        # Mutate typeflag (offset 156, 1 byte)
        # '0': regular, '1': hardlink, '2': symlink, '5': directory, '7': contiguous
        flags = [0x30_u8, 0x31_u8, 0x32_u8, 0x33_u8, 0x34_u8, 0x35_u8, 0x36_u8, 0x37_u8, 0x00_u8, 0xFF_u8]
        buffer[156] = context.prng.choice(flags)
        mutated = true
      else
        # Mutate file data block after 512-byte header
        if buffer.size > 512
          data_len = buffer.size - 512
          pos = 512 + context.prng.rand(data_len)
          span = Math.min(context.prng.rand(1..32), buffer.size - pos)
          span.times do |off|
            buffer[pos + off] ^= context.prng.rand(1..255).to_u8
          end
          mutated = true
        else
          # Fallback: mutate linkname (offset 157..256)
          link = context.prng.choice(["/etc/shadow", "C:\\boot.ini", "../symlink_target"])
          len = Math.min(link.size, 99)
          buffer.replace_range(157, len, link.to_slice[0, len])
          buffer[157 + len] = 0x00_u8
          mutated = true
        end
      end

      # Recalculate 8-byte octal header checksum (offset 148..155)
      # Checksum is computed over 512 bytes with chksum field (148..155) treated as ASCII spaces 0x20
      if mutated
        chksum = calculate_checksum(buffer)
        chksum_str = sprintf("%06o\0 ", chksum)
        buffer.replace_range(148, 8, chksum_str.to_slice)
        context.record_mutation(name)
        true
      else
        false
      end
    rescue
      false
    end

    def calculate_checksum(buffer : Buffer) : UInt32
      sum = 0_u32
      512.times do |i|
        byte_val = (i >= 148 && i < 156) ? 0x20_u8 : buffer[i]
        sum += byte_val.to_u32
      end
      sum
    end
  end
end
