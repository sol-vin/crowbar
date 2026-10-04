require "./base"

module Crowbar::Rules
  # Structure-preserving rule for Doom WAD files (IWAD and PWAD).
  # Preserves 12-byte WAD header (identification, lump count, directory offset)
  # and 16-byte directory lump entries (filepos, size, 8-byte ASCII name),
  # while mutating lump directory tables, lump names, and lump data payloads
  # (THINGS coordinates/types, VERTEXES, LINEDEFS, and sound/graphics lumps).
  class WADRule < Rule
    IWAD_MAGIC = Bytes[0x49, 0x57, 0x41, 0x44] # "IWAD"
    PWAD_MAGIC = Bytes[0x50, 0x57, 0x41, 0x44] # "PWAD"

    struct LumpEntry
      getter filepos : Int32
      property size : Int32
      getter name : String
      getter entry_offset : Int32

      def initialize(@filepos : Int32, @size : Int32, @name : String, @entry_offset : Int32)
      end
    end

    def name : String
      "wad"
    end

    def description : String
      "Structure-preserving Doom WAD (IWAD/PWAD) directory and lump payload mutation"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 12
      magic = buffer[0, 4].to_slice
      return false unless magic == IWAD_MAGIC || magic == PWAD_MAGIC

      numlumps = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[4, 4].to_slice).to_i32 rescue 0
      infotableofs = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[8, 4].to_slice).to_i32 rescue 0

      # numlumps and infotableofs sanity check
      return false if numlumps < 0 || infotableofs < 12
      infotableofs + (numlumps * 16) <= buffer.size
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      numlumps = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[4, 4].to_slice).to_i32 rescue 0
      infotableofs = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[8, 4].to_slice).to_i32 rescue 0
      return false if numlumps == 0

      lumps = parse_directory(buffer, numlumps, infotableofs)
      return false if lumps.empty?

      action = context.prng.rand(4)
      mutated = false

      case action
      when 0
        # Mutate lump data payload
        non_empty = lumps.reject { |l| l.size <= 0 || l.filepos + l.size > buffer.size }
        if !non_empty.empty?
          lump = context.prng.choice(non_empty)
          mutate_lump_payload(lump, buffer, context)
          mutated = true
        end
      when 1
        # Mutate a lump directory entry (name or size)
        lump = context.prng.choice(lumps)
        mutate_lump_entry(lump, buffer, context)
        mutated = true
      when 2
        # Swap two directory entries in the table
        if lumps.size >= 2
          idx1 = context.prng.rand(lumps.size)
          idx2 = context.prng.rand(lumps.size)
          if idx1 != idx2
            swap_directory_entries(lumps[idx1], lumps[idx2], buffer)
            mutated = true
          end
        end
      else
        # Mutate WAD Header: toggle IWAD <-> PWAD or fuzz lump count
        if context.prng.rand_bool
          # Toggle IWAD / PWAD
          if buffer[0] == 0x49_u8 # 'I'
            buffer[0] = 0x50_u8   # 'P'
          else
            buffer[0] = 0x49_u8 # 'I'
          end
          mutated = true
        else
          # Fuzz numlumps off-by-one or boundary
          bad_counts = [numlumps &+ 1, numlumps > 0 ? numlumps - 1 : 0, 0, 65535]
          new_count = context.prng.choice(bad_counts).to_u32
          IO::ByteFormat::LittleEndian.encode(new_count, buffer[4, 4])
          mutated = true
        end
      end

      if mutated
        context.record_mutation(name)
        true
      else
        false
      end
    rescue
      false
    end

    def parse_directory(buffer : Buffer, numlumps : Int32, infotableofs : Int32) : Array(LumpEntry)
      lumps = [] of LumpEntry
      pos = infotableofs

      numlumps.times do
        break if pos + 16 > buffer.size
        filepos = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[pos, 4].to_slice).to_i32 rescue 0
        size = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[pos + 4, 4].to_slice).to_i32 rescue 0

        # Lump name: 8 bytes, null-padded ASCII
        name_slice = buffer[pos + 8, 8].to_slice
        name_str = String.new(name_slice).rstrip('\0') rescue "UNKNOWN"

        lumps << LumpEntry.new(filepos, size, name_str, pos)
        pos += 16
      end

      lumps
    end

    private def mutate_lump_payload(lump : LumpEntry, buffer : Buffer, context : Context)
      len = lump.size
      start = lump.filepos
      return if len <= 0 || start + len > buffer.size

      # Specialize mutation by known Doom lump names
      case lump.name
      when "THINGS"
        # THINGS lump: array of 10-byte records
        # x (int16), y (int16), angle (uint16), type (uint16), flags (uint16)
        num_things = len // 10
        if num_things > 0
          thing_idx = context.prng.rand(num_things)
          rec_off = start + (thing_idx * 10)
          case context.prng.rand(3)
          when 0
            # Mutate Coordinates (x or y)
            off = rec_off + (context.prng.rand_bool ? 0 : 2)
            coords = [-32768_i16, 32767_i16, 0_i16, -1_i16, 1_i16]
            IO::ByteFormat::LittleEndian.encode(context.prng.choice(coords), buffer[off, 2])
          when 1
            # Mutate Thing Type (e.g. 1=Player1, 16=Cyberdemon, 0=bad, 65535=max)
            types = [0_u16, 1_u16, 16_u16, 7_u16, 9_u16, 65535_u16, 3004_u16]
            IO::ByteFormat::LittleEndian.encode(context.prng.choice(types), buffer[rec_off + 6, 2])
          else
            # Mutate flags
            flags = [0_u16, 7_u16, 15_u16, 65535_u16]
            IO::ByteFormat::LittleEndian.encode(context.prng.choice(flags), buffer[rec_off + 8, 2])
          end
          return
        end
      when "VERTEXES"
        # VERTEXES: array of 4-byte records (x: int16, y: int16)
        num_verts = len // 4
        if num_verts > 0
          v_idx = context.prng.rand(num_verts)
          rec_off = start + (v_idx * 4) + (context.prng.rand_bool ? 0 : 2)
          coords = [-32768_i16, 32767_i16, 0_i16]
          IO::ByteFormat::LittleEndian.encode(context.prng.choice(coords), buffer[rec_off, 2])
          return
        end
      when "LINEDEFS"
        # LINEDEFS: array of 14-byte records
        num_lines = len // 14
        if num_lines > 0
          l_idx = context.prng.rand(num_lines)
          rec_off = start + (l_idx * 14)
          # Mutate flags (offset 4, 2 bytes) or special type (offset 6, 2 bytes)
          off = rec_off + (context.prng.rand_bool ? 4 : 6)
          IO::ByteFormat::LittleEndian.encode(context.prng.next_u32.to_u16, buffer[off, 2])
          return
        end
      end

      # Generic lump mutation: flip bits or random bytes
      mut_count = [len, context.prng.rand(1..8)].min
      mut_count.times do
        idx = start + context.prng.rand(len)
        buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
      end
    end

    private def mutate_lump_entry(lump : LumpEntry, buffer : Buffer, context : Context)
      entry_off = lump.entry_offset

      if context.prng.rand_bool
        # Mutate lump name (8 bytes ASCII at offset 8)
        names = ["E1M1", "MAP01", "THINGS", "LINEDEFS", "SIDEDEFS", "VERTEXES", "PLAYPAL", "COLORMAP", "F_START", "F_END", "ENDDOOM", "DEMO1"]
        chosen = context.prng.choice(names)
        name_buf = Bytes.new(8, 0_u8)
        chosen.to_slice[0, [chosen.bytesize, 8].min].copy_to(name_buf)
        name_buf.copy_to(buffer[entry_off + 8, 8])
      else
        # Mutate lump size (offset 4, 4 bytes LE)
        bad_sizes = [0_u32, 1_u32, lump.size.to_u32 &+ 1_u32, 65535_u32, 4294967295_u32]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(bad_sizes), buffer[entry_off + 4, 4])
      end
    end

    private def swap_directory_entries(lump1 : LumpEntry, lump2 : LumpEntry, buffer : Buffer)
      entry1 = buffer[lump1.entry_offset, 16].dup
      entry2 = buffer[lump2.entry_offset, 16].dup
      entry2.copy_to(buffer[lump1.entry_offset, 16])
      entry1.copy_to(buffer[lump2.entry_offset, 16])
    end
  end
end
