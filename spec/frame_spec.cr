require "./spec_helper"
require "../src/crowbar/dsl/frame_builder"
require "digest/crc32"

describe "Declarative Binary Protocol Framing" do
  it "defines and assembles binary packets with automatic length and CRC32 fields" do
    fuzzer = Crowbar.define do
      seed 42_u64

      frame :packet do
        field :magic, default: Bytes[0xAA, 0x55], mutate: false
        field :version, kind: :u8, default: 1_u8, mutate: false
        field :payload_len, kind: :u16_be, relates_to: :payload
        field :payload, default: "PING_PAYLOAD"
        field :crc, kind: :crc32, covers: [:magic, :version, :payload_len, :payload]
      end
    end

    fuzzer.frames.has_key?("packet").should be_true
    frame = fuzzer.frames["packet"]

    baseline = frame.build_baseline
    baseline.size.should eq(2 + 1 + 2 + 12 + 4) # magic(2) + ver(1) + len(2) + payload(12) + crc(4) = 21

    # Check magic
    baseline[0..1].should eq(Bytes[0xAA, 0x55])

    # Check payload length
    stored_len = IO::ByteFormat::BigEndian.decode(UInt16, baseline[3, 2])
    stored_len.should eq(12_u16)

    # Check CRC32
    stored_crc = IO::ByteFormat::BigEndian.decode(UInt32, baseline[17, 4])
    computed_crc = Digest::CRC32.checksum(baseline[0...17])
    stored_crc.should eq(computed_crc)
  end

  it "mutates frame payloads and recomputes lengths and checksums automatically" do
    fuzzer = Crowbar.define do
      seed 1337_u64

      frame :telemetry do
        field :magic, default: Bytes[0xBE, 0xEF], mutate: false
        field :length, kind: :u16_be, relates_to: :data
        field :data, default: "STATUS:OK"
        field :checksum, kind: :crc32
      end
    end

    mutant = fuzzer.fuzz_frame(:telemetry)
    mutant.size.should be >= 8

    # Magic preserved
    mutant[0..1].should eq(Bytes[0xBE, 0xEF])

    # Length field synchronized with actual data size
    actual_data_len = mutant.size - 2 - 2 - 4
    stored_len = IO::ByteFormat::BigEndian.decode(UInt16, mutant[2, 2])
    stored_len.should eq(actual_data_len.to_u16)

    # CRC32 verified
    stored_crc = IO::ByteFormat::BigEndian.decode(UInt32, mutant[(mutant.size - 4), 4])
    computed_crc = Digest::CRC32.checksum(mutant[0...(mutant.size - 4)])
    stored_crc.should eq(computed_crc)
  end
end
