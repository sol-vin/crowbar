require "./buffer"

module Crowbar
  # Output envelope templating engine.
  # Replaces '%f' or '{{data}}' within an inline string or template file
  # with the mutated payload bytes, enabling protocol wrapper fuzzing.
  module Template
    # Renders an output envelope wrapping data within a template specification.
    # Spec can be an inline string or path to an existing file.
    # Supported placeholders: '%f' (Radamsa standard) or '{{data}}'.
    def self.render(template_spec : String, data : Buffer | Bytes) : Buffer
      template_bytes = if File.exists?(template_spec)
                         File.read(template_spec).to_slice
                       else
                         template_spec.to_slice
                       end
      data_slice = data.is_a?(Buffer) ? data.to_slice : data

      # Check for %f (0x25, 0x66)
      placeholder_f = "%f".to_slice
      placeholder_mustache = "{{data}}".to_slice

      pos = find_subslice(template_bytes, placeholder_f)
      needle_len = placeholder_f.size
      if pos.nil?
        pos = find_subslice(template_bytes, placeholder_mustache)
        needle_len = placeholder_mustache.size
      end

      if pos
        prefix = template_bytes[0...pos]
        suffix_start = pos + needle_len
        suffix = template_bytes[suffix_start...template_bytes.size]

        result = Bytes.new(prefix.size + data_slice.size + suffix.size)
        prefix.copy_to(result.to_slice[0, prefix.size])
        data_slice.copy_to(result.to_slice[prefix.size, data_slice.size])
        suffix.copy_to(result.to_slice[prefix.size + data_slice.size, suffix.size])
        Buffer.new(result)
      else
        # Fallback: append data to template
        result = Bytes.new(template_bytes.size + data_slice.size)
        template_bytes.copy_to(result.to_slice[0, template_bytes.size])
        data_slice.copy_to(result.to_slice[template_bytes.size, data_slice.size])
        Buffer.new(result)
      end
    end

    private def self.find_subslice(haystack : Bytes, needle : Bytes) : Int32?
      return nil if needle.empty? || haystack.size < needle.size
      max_idx = haystack.size - needle.size
      0.upto(max_idx) do |i|
        match = true
        needle.each_with_index do |b, j|
          if haystack[i + j] != b
            match = false
            break
          end
        end
        return i if match
      end
      nil
    end
  end
end
