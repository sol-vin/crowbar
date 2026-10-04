require "./base"

module Crowbar::Rules
  # Structure-preserving rule for Portable Document Format (PDF) files.
  # Preserves %PDF- header, indirect object framing (N 0 obj ... endobj),
  # stream delimiters (stream ... endstream), and trailer xref offsets,
  # while mutating dictionary keys/values, numeric bounds, filters, and stream bodies.
  class PDFRule < Rule
    PDF_MAGIC = "%PDF-".to_slice

    def name : String
      "pdf"
    end

    def description : String
      "Structure-preserving PDF object, dictionary, stream, and xref mutation"
    end

    def match?(buffer : Buffer) : Bool
      return false if buffer.size < 8
      buffer[0, 5].to_slice == PDF_MAGIC
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      return false unless match?(buffer)

      raw = String.new(buffer.to_slice) rescue nil
      return false unless raw

      action = context.prng.rand(4)
      mutated = false

      case action
      when 0
        # Mutate numeric dictionary attributes (/Length, /Width, /Height, /Count, /Size)
        num_keys = ["/Length", "/Width", "/Height", "/Count", "/Size", "/Rotate"]
        chosen_key = context.prng.choice(num_keys)

        if idx = raw.index(chosen_key)
          # Look for subsequent digits
          val_start = idx + chosen_key.size
          while val_start < raw.size && (raw[val_start] == ' ' || raw[val_start] == '\t')
            val_start += 1
          end

          val_end = val_start
          while val_end < raw.size && raw[val_end].ascii_number?
            val_end += 1
          end

          if val_end > val_start
            boundary_nums = ["0", "1", "65535", "2147483647", "-1", "999999"]
            new_num = context.prng.choice(boundary_nums)
            buffer.replace_range(val_start, val_end - val_start, new_num.to_slice)
            mutated = true
          end
        end
      when 1
        # Mutate stream payload between "stream" and "endstream"
        if stream_pos = raw.index("stream")
          # Advance past newline
          p = stream_pos + 6
          p += 1 if p < raw.size && raw[p] == '\r'
          p += 1 if p < raw.size && raw[p] == '\n'

          if end_pos = raw.index("endstream", p)
            stream_len = end_pos - p
            if stream_len > 0
              mut_count = [stream_len, context.prng.rand(1..6)].min
              mut_count.times do
                idx = p + context.prng.rand(stream_len)
                buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
              end
              mutated = true
            end
          end
        end
      when 2
        # Mutate Filter or Type names in dictionaries
        filter_names = ["/FlateDecode", "/ASCIIHexDecode", "/ASCII85Decode", "/LZWDecode", "/RunLengthDecode", "/CCITTFaxDecode", "/JBIG2Decode", "/DCTDecode"]
        filter_names.each do |fn|
          if idx = raw.index(fn)
            replacement = context.prng.choice(filter_names.reject { |f| f == fn })
            buffer.replace_range(idx, fn.bytesize, replacement.to_slice)
            mutated = true
            break
          end
        end
      else
        # Fuzz arbitrary bytes within an object body (between obj and endobj)
        if obj_pos = raw.index(" obj")
          if endobj_pos = raw.index("endobj", obj_pos)
            body_start = obj_pos + 4
            body_len = endobj_pos - body_start
            if body_len > 8
              mut_idx = body_start + context.prng.rand(body_len)
              buffer[mut_idx] = buffer[mut_idx] ^ (1_u8 << context.prng.rand(8))
              mutated = true
            end
          end
        end
      end

      # Fallback: bitflip a non-header byte
      if !mutated && buffer.size > 16
        idx = 8 + context.prng.rand(buffer.size - 16)
        buffer[idx] = buffer[idx] ^ (1_u8 << context.prng.rand(8))
        mutated = true
      end

      # Synchronize startxref offset if present
      if mutated
        synchronize_startxref(buffer)
        context.record_mutation(name)
        true
      else
        false
      end
    rescue
      false
    end

    private def synchronize_startxref(buffer : Buffer)
      str = String.new(buffer.to_slice) rescue return
      xref_pos = str.rindex("xref")
      startxref_pos = str.rindex("startxref")

      return unless xref_pos && startxref_pos && startxref_pos > xref_pos

      val_start = startxref_pos + 9
      while val_start < str.size && (str[val_start] == ' ' || str[val_start] == '\r' || str[val_start] == '\n')
        val_start += 1
      end

      val_end = val_start
      while val_end < str.size && str[val_end].ascii_number?
        val_end += 1
      end

      if val_end > val_start
        new_offset = xref_pos.to_s
        buffer.replace_range(val_start, val_end - val_start, new_offset.to_slice)
      end
    end
  end
end
