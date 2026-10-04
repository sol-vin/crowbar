require "digest/crc32"
require "../buffer"
require "../context"

module Crowbar
  # Field definition within a binary protocol Frame
  class FrameField
    property name : String
    property kind : Symbol
    property size : Int32?
    property default_data : Bytes
    property relates_to : String?
    property covers : Array(String)?
    property mutable : Bool
    property mutators : Array(Symbol)

    def initialize(
      name : String | Symbol,
      @kind : Symbol = :raw,
      @size : Int32? = nil,
      default : Bytes | String | Int | Nil = nil,
      relates_to : String | Symbol | Nil = nil,
      covers : Array(String | Symbol) | Nil = nil,
      @mutable : Bool = true,
      @mutators : Array(Symbol) = [] of Symbol,
    )
      @name = name.to_s
      @relates_to = relates_to.try(&.to_s)
      @covers = covers.try(&.map(&.to_s))

      @default_data = case default
                      when Bytes
                        default
                      when String
                        default.to_slice
                      when UInt8, Int8
                        Bytes[default.to_u8]
                      when UInt16, Int16
                        b = Bytes.new(2)
                        if @kind == :u16_le
                          IO::ByteFormat::LittleEndian.encode(default.to_u16, b)
                        else
                          IO::ByteFormat::BigEndian.encode(default.to_u16, b)
                        end
                        b
                      when UInt32, Int32
                        b = Bytes.new(4)
                        if @kind == :u32_le
                          IO::ByteFormat::LittleEndian.encode(default.to_u32, b)
                        else
                          IO::ByteFormat::BigEndian.encode(default.to_u32, b)
                        end
                        b
                      when UInt64, Int64
                        b = Bytes.new(8)
                        IO::ByteFormat::BigEndian.encode(default.to_u64, b)
                        b
                      else
                        if s = @size
                          Bytes.new(s, 0_u8)
                        else
                          Bytes.empty
                        end
                      end
    end
  end

  # Declarative protocol frame definition orchestrating fields, auto-lengths, and checksums
  class FrameDefinition
    getter name : String
    getter fields : Array(FrameField)

    def initialize(@name : String)
      @fields = [] of FrameField
    end

    def add_field(field : FrameField)
      @fields << field
    end

    def field_by_name(name : String) : FrameField?
      @fields.find { |f| f.name == name }
    end

    # Assembles a buffer from field byte slices, automatically updating lengths and checksums
    def assemble(field_data : Hash(String, Bytes)) : Buffer
      # 1. Update length fields that point to payload fields
      @fields.each do |f|
        if target_name = f.relates_to
          target_bytes = field_data[target_name]? || Bytes.empty
          target_len = target_bytes.size
          encoded = case f.kind
                    when :u8
                      Bytes[target_len.to_u8]
                    when :u16_le
                      b = Bytes.new(2)
                      IO::ByteFormat::LittleEndian.encode(target_len.to_u16, b)
                      b
                    when :u16_be, :u16
                      b = Bytes.new(2)
                      IO::ByteFormat::BigEndian.encode(target_len.to_u16, b)
                      b
                    when :u32_le
                      b = Bytes.new(4)
                      IO::ByteFormat::LittleEndian.encode(target_len.to_u32, b)
                      b
                    when :u32_be, :u32
                      b = Bytes.new(4)
                      IO::ByteFormat::BigEndian.encode(target_len.to_u32, b)
                      b
                    else
                      b = Bytes.new(2)
                      IO::ByteFormat::BigEndian.encode(target_len.to_u16, b)
                      b
                    end
          field_data[f.name] = encoded
        end
      end

      # 2. Update checksum fields (e.g. CRC32)
      @fields.each do |f|
        if f.kind == :crc32
          covered_names = f.covers || @fields.reject { |other| other.name == f.name }.map(&.name)
          io = IO::Memory.new
          covered_names.each do |cname|
            if b = field_data[cname]?
              io.write(b)
            end
          end
          checksum = Digest::CRC32.checksum(io.to_slice)
          crc_b = Bytes.new(4)
          IO::ByteFormat::BigEndian.encode(checksum, crc_b)
          field_data[f.name] = crc_b
        end
      end

      # 3. Assemble final contiguous buffer
      result = IO::Memory.new
      @fields.each do |f|
        bytes = field_data[f.name]? || f.default_data
        result.write(bytes)
      end
      Buffer.new(result.to_slice)
    end

    # Builds a default baseline packet for this frame
    def build_baseline : Buffer
      data = Hash(String, Bytes).new
      @fields.each do |f|
        data[f.name] = f.default_data.dup
      end
      assemble(data)
    end

    # Mutates the frame: mutates mutable fields, then re-synchronizes lengths and checksums
    def mutate(context : Context, pool : MutatorPool) : Buffer
      data = Hash(String, Bytes).new
      @fields.each do |f|
        data[f.name] = f.default_data.dup
      end

      # Select mutable fields and mutate
      mutable_fields = @fields.select(&.mutable)
      unless mutable_fields.empty?
        target_field = context.prng.choice(mutable_fields)
        current_val = data[target_field.name]? || target_field.default_data
        field_buf = Buffer.new(current_val)

        pool.mutate(context, field_buf)
        data[target_field.name] = field_buf.to_slice
      end

      assemble(data)
    end
  end

  # DSL builder for defining structured binary protocol frames
  class FrameBuilder
    getter frame : FrameDefinition

    def initialize(name : String | Symbol)
      @frame = FrameDefinition.new(name.to_s)
    end

    # Define a frame field
    def field(
      name : String | Symbol,
      kind : Symbol = :raw,
      bytes size : Int32? = nil,
      default = nil,
      relates_to : String | Symbol | Nil = nil,
      covers : Array(String | Symbol) | Nil = nil,
      mutate : Bool = true,
      mutators : Array(Symbol) = [] of Symbol,
    )
      ff = FrameField.new(
        name: name,
        kind: kind,
        size: size,
        default: default,
        relates_to: relates_to,
        covers: covers,
        mutable: mutate,
        mutators: mutators
      )
      @frame.add_field(ff)
    end
  end
end
