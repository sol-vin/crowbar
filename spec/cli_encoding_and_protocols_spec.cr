require "./spec_helper"
require "../src/crowbar/cli/app"
require "file_utils"
require "json"

def run_codec_cli(args : Array(String), input : String = "") : Tuple(Int32, String, String)
  in_io = IO::Memory.new(input)
  out_io = IO::Memory.new
  err_io = IO::Memory.new

  exit_code = 0
  app = Crowbar::CLI::App.new(
    in_io: in_io,
    out_io: out_io,
    err_io: err_io,
    exit_handler: ->(code : Int32) {
      exit_code = code
      raise Crowbar::CLI::ExitException.new(code)
    }
  )

  begin
    app.run(args)
  rescue ex : Crowbar::CLI::ExitException
    # Captured exit code
  end

  {exit_code, out_io.to_s, err_io.to_s}
end

describe "Crowbar CLI Encoding Codecs & New Protocol Rules" do
  test_tmp_dir = File.join(Dir.tempdir, "crowbar_codec_test_#{Random.rand(10000)}")

  before_each do
    FileUtils.mkdir_p(test_tmp_dir)
    ENV["CROWBAR_SESSION_DIR"] = test_tmp_dir
  end

  after_each do
    FileUtils.rm_rf(test_tmp_dir) if Dir.exists?(test_tmp_dir)
    ENV.delete("CROWBAR_SESSION_DIR")
  end

  after_all do
    FileUtils.rm_rf(test_tmp_dir) if Dir.exists?(test_tmp_dir)
    ENV.delete("CROWBAR_SESSION_DIR")
  end

  describe "Hex Representation Codec (-I hex, -O hex)" do
    it "decodes hex input, mutates binary payload, and encodes output to hex" do
      code, stdout, _ = run_codec_cli(["-I", "hex", "-O", "hex", "-s", "42", "48656c6c6f576f726c64"])
      code.should eq(0)
      stdout.should_not be_empty
      # Must be valid hex characters
      stdout.strip.matches?(/^[0-9a-f]+$/).should be_true
    end

    it "accepts inline payload via --data flag" do
      code, stdout, _ = run_codec_cli(["--data", "deadbeef01020304", "-I", "hex", "-O", "hex", "-s", "100"])
      code.should eq(0)
      stdout.strip.matches?(/^[0-9a-f]+$/).should be_true
    end
  end

  describe "C-Style Escape Codec (-I escape, -O escape)" do
    it "decodes escaped strings containing null bytes and emits escaped output" do
      code, stdout, _ = run_codec_cli(["-I", "escape", "-O", "escape", "-s", "42", "USER \\x00\\xff\\r\\n"])
      code.should eq(0)
      stdout.should_not be_empty
      stdout.should contain("USER ")
    end
  end

  describe "Bitstring Codec (-I bit, -O bit)" do
    it "decodes bitstrings and emits valid 8-bit octet strings" do
      code, stdout, _ = run_codec_cli(["-I", "bit", "-O", "bit", "-s", "42", "0b0100000101000010"])
      code.should eq(0)
      stdout.strip.matches?(/^[01]+$/).should be_true
      (stdout.strip.size % 8).should eq(0)
    end
  end

  describe "Auto-Detection of New Storage & Network Rules (--auto)" do
    it "auto-detects 7z archives and synchronizes StartHeader CRC32" do
      hdr = Bytes.new(32, 0_u8)
      Bytes[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C].copy_to(hdr[0, 6])
      IO::ByteFormat::LittleEndian.encode(100_u64, hdr[12, 8])
      IO::ByteFormat::LittleEndian.encode(50_u64, hdr[20, 8])
      init_crc = Digest::CRC32.checksum(hdr[12, 20])
      IO::ByteFormat::LittleEndian.encode(init_crc, hdr[8, 4])

      code, stdout, _ = run_codec_cli(["--auto", "-s", "42"], input: String.new(hdr))
      code.should eq(0)
      out_bytes = stdout.to_slice
      out_bytes[0, 6].should eq(Bytes[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
      expected_crc = Digest::CRC32.checksum(out_bytes[12, 20])
      actual_crc = IO::ByteFormat::LittleEndian.decode(UInt32, out_bytes[8, 4])
      actual_crc.should eq(expected_crc)
    end

    it "auto-detects TAR archives and preserves 512-byte block structure" do
      block = Bytes.new(512, 0_u8)
      "archive.txt".to_slice.copy_to(block[0, 11])
      "0000644\0".to_slice.copy_to(block[100, 8])
      "00000000010\0".to_slice.copy_to(block[124, 12])
      block[156] = 0x30_u8
      "ustar\0".to_slice.copy_to(block[257, 6])
      "00".to_slice.copy_to(block[263, 2])
      init_sum = 0_u32
      512.times { |i| init_sum += (i >= 148 && i < 156 ? 0x20_u8 : block[i]).to_u32 }
      sprintf("%06o\0 ", init_sum).to_slice.copy_to(block[148, 8])

      code, stdout, _ = run_codec_cli(["--auto", "-s", "42"], input: String.new(block))
      code.should eq(0)
      stdout.to_slice.size.should eq(512)
      stdout.to_slice[257, 5].should eq("ustar".to_slice)
    end

    it "auto-detects raw IPv4 packets and maintains valid RFC 791 checksum" do
      pkt = Bytes.new(28, 0_u8)
      pkt[0] = 0x45_u8
      IO::ByteFormat::BigEndian.encode(28_u16, pkt[2, 2])
      pkt[8] = 64_u8
      pkt[9] = 17_u8 # UDP
      Bytes[10, 0, 0, 1].copy_to(pkt[12, 4])
      Bytes[10, 0, 0, 2].copy_to(pkt[16, 4])
      # UDP header
      IO::ByteFormat::BigEndian.encode(53_u16, pkt[22, 2])
      IO::ByteFormat::BigEndian.encode(8_u16, pkt[24, 2])

      code, stdout, _ = run_codec_cli(["--auto", "-s", "42"], input: String.new(pkt))
      code.should eq(0)
      out_pkt = stdout.to_slice
      ((out_pkt[0] >> 4) & 0x0F).should eq(4)

      # Checksum fold verification
      sum = 0_u32
      (0...20).step(2) do |i|
        word = IO::ByteFormat::BigEndian.decode(UInt16, out_pkt[i, 2])
        sum += word.to_u32
      end
      while (sum >> 16) > 0
        sum = (sum & 0xFFFF_u32) + (sum >> 16)
      end
      sum.should eq(0xFFFF_u32)
    end

    it "auto-detects Markdown documents" do
      doc = "# API Specification\n\nCheckout the [documentation](https://example.com/docs).\n"
      code, stdout, _ = run_codec_cli(["--auto", "-s", "42"], input: doc)
      code.should eq(0)
      stdout.should_not eq(doc)
      (stdout.includes?("[documentation]") || stdout.includes?("#")).should be_true
    end
  end

  describe "Session Integration with In/Out Formats" do
    it "persists and applies in/out encodings across session next invocations" do
      sess_id = "codec_sess"

      # 1. Initialize session with hex input and format flags
      code_init, out_init, _ = run_codec_cli(["session", sess_id, "next", "-I", "hex", "-O", "hex"], input: "48656c6c6f")
      code_init.should eq(0)
      out_init.strip.matches?(/^[0-9a-f]+$/).should be_true

      # 2. Setup format configuration explicitly to verify setup command
      code_setup, out_setup, _ = run_codec_cli(["session", sess_id, "setup", "--in-format", "hex", "--out-format", "hex"])
      code_setup.should eq(0)
      out_setup.should contain("Set input encoding to 'hex'")
      out_setup.should contain("Set output encoding to 'hex'")

      # 3. Next with piped hex baseline reusing persisted configuration
      code_next, out_next, _ = run_codec_cli(["session", sess_id, "next"], input: "48656c6c6f")
      code_next.should eq(0)
      out_next.strip.matches?(/^[0-9a-f]+$/).should be_true

      # 4. Status inspects format configuration
      code_stat, out_stat, _ = run_codec_cli(["session", sess_id, "status"])
      code_stat.should eq(0)
      out_stat.should contain("In Format:")
      out_stat.should contain("hex")
      out_stat.should contain("Out Format:")
    end
  end
end
