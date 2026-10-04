require "./base"

module Crowbar::Rules
  # Structure-preserving rule for Windows Bitmap (BMP) files.
  # Preserves the 14-byte BITMAPFILEHEADER ("BM") and DIB header framing,
  # while mutating dimensions, bit depths, compression schemes, color palettes,
  # and pixel raster data, and automatically synchronizing file size and raster offsets.
  class BMPRule < Rule
    def name : String
      "bmp"
    end

    def description : String
      "Structure-preserving BMP header, DIB table, and pixel raster mutation"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 54
      # "BM" magic bytes
      return false unless buffer[0] == 0x42_u8 && buffer[1] == 0x4D_u8
      # DIB header size should be at least 40 bytes (BITMAPINFOHEADER)
      dib_size = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[14, 4].to_slice)
      dib_size >= 40_u32
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      data_offset = IO::ByteFormat::LittleEndian.decode(UInt32, buffer[10, 4].to_slice).to_i32 rescue 54
      data_offset = 54 if data_offset < 54 || data_offset > buffer.size

      action = context.prng.rand(5)
      case action
      when 0
        # Mutate Dimensions: Width (offset 18) or Height (offset 22)
        if context.prng.rand_bool
          # Width (4 bytes signed LE)
          widths = [0, 1, -1, 65535, 1048576, Int32::MAX]
          new_w = context.prng.choice(widths)
          IO::ByteFormat::LittleEndian.encode(new_w, buffer[18, 4])
        else
          # Height (4 bytes signed LE: negative indicates top-down bitmap)
          heights = [0, 1, -1, -100, 65535, Int32::MAX, Int32::MIN]
          new_h = context.prng.choice(heights)
          IO::ByteFormat::LittleEndian.encode(new_h, buffer[22, 4])
        end
      when 1
        # Mutate Bit Depth (offset 28, 2 bytes LE) and Planes (offset 26, 2 bytes LE)
        if context.prng.rand_bool
          bad_bpp = [0_u16, 2_u16, 3_u16, 5_u16, 7_u16, 12_u16, 48_u16, 64_u16, 255_u16]
          IO::ByteFormat::LittleEndian.encode(context.prng.choice(bad_bpp), buffer[28, 2])
        else
          bad_planes = [0_u16, 2_u16, 255_u16, 65535_u16]
          IO::ByteFormat::LittleEndian.encode(context.prng.choice(bad_planes), buffer[26, 2])
        end
      when 2
        # Mutate Compression Mode (offset 30, 4 bytes LE)
        # 0=BI_RGB, 1=BI_RLE8, 2=BI_RLE4, 3=BI_BITFIELDS, 4=BI_JPEG, 5=BI_PNG
        compressions = [0_u32, 1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 255_u32, 4294967295_u32]
        IO::ByteFormat::LittleEndian.encode(context.prng.choice(compressions), buffer[30, 4])
      when 3
        # Mutate Color Count or Image Size fields (offsets 34, 46, 50)
        field_off = context.prng.choice([34, 46, 50])
        val = context.prng.choice([0_u32, 1_u32, 256_u32, 65536_u32, 4294967295_u32])
        IO::ByteFormat::LittleEndian.encode(val, buffer[field_off, 4])
      else
        # Mutate Pixel Raster bytes (between data_offset and buffer.size)
        raster_len = buffer.size - data_offset
        if raster_len > 0
          mut_bytes = [raster_len, context.prng.rand(1..8)].min
          mut_bytes.times do
            idx = data_offset + context.prng.rand(raster_len)
            buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
          end
        end
      end

      # Synchronize total file size at offset 2 (4 bytes LE)
      IO::ByteFormat::LittleEndian.encode(buffer.size.to_u32, buffer[2, 4])

      context.record_mutation(name)
      true
    rescue
      false
    end
  end
end
