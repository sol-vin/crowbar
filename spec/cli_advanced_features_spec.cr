require "./spec_helper"
require "../src/crowbar/cli/app"
require "file_utils"
require "json"

def run_adv_cli(args : Array(String), input : String = "") : Tuple(Int32, String, String)
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

describe "Crowbar Advanced CLI Features & Option Combinations" do
  test_tmp_dir = File.join(Dir.tempdir, "crowbar_cli_adv_#{Random.rand(10000)}")

  before_each do
    FileUtils.mkdir_p(test_tmp_dir)
  end

  after_each do
    FileUtils.rm_rf(test_tmp_dir) if Dir.exists?(test_tmp_dir)
  end

  describe "Multi-Sample Splicing via CLI Positional Arguments" do
    it "loads multiple input files and performs inter-sample splicing" do
      f1 = File.join(test_tmp_dir, "sample_a.txt")
      f2 = File.join(test_tmp_dir, "sample_b.txt")
      File.write(f1, "COMMON_PREFIX_FIRST_STREAM_CONTENT_99999")
      File.write(f2, "COMMON_PREFIX_SECOND_STREAM_CONTENT_88888")

      code, stdout, stderr = run_adv_cli([f1, f2, "-m", "fuse", "-s", "42"])
      code.should eq(0)
      stdout.should_not be_empty
      stdout.should_not eq("COMMON_PREFIX_FIRST_STREAM_CONTENT_99999")
    end

    it "fails cleanly when primary positional input file is missing" do
      code, _, stderr = run_adv_cli(["missing_primary_file_xyz.bin"])
      code.should eq(1)
      stderr.should contain("Error: File 'missing_primary_file_xyz.bin' does not exist")
    end

    it "gracefully ignores nonexistent secondary samples" do
      f1 = File.join(test_tmp_dir, "valid_sample.txt")
      File.write(f1, "Valid sample content for fuzzing")

      code, stdout, _ = run_adv_cli([f1, "nonexistent_secondary_sample.txt", "-s", "42"])
      code.should eq(0)
      stdout.should_not be_empty
    end
  end

  describe "Output Templating with -t / --template" do
    it "wraps payload in template using %f placeholder" do
      code, stdout, _ = run_adv_cli(["-t", "HTTP/1.1 200 OK\r\n\r\n%f", "-s", "42"], input: "hello world")
      code.should eq(0)
      stdout.should start_with("HTTP/1.1 200 OK\r\n\r\n")
      stdout.size.should be > "HTTP/1.1 200 OK\r\n\r\n".size
    end

    it "wraps payload in template using {{data}} mustache placeholder" do
      code, stdout, _ = run_adv_cli(["--template", "{\"data\": {{data}}}", "-s", "42"], input: "12345")
      code.should eq(0)
      stdout.should start_with("{\"data\": ")
      stdout.should end_with("}")
    end

    it "loads template from an external file when path exists" do
      tmpl_file = File.join(test_tmp_dir, "wrapper.tmpl")
      File.write(tmpl_file, "BEGIN_WRAPPER\n%f\nEND_WRAPPER")

      code, stdout, _ = run_adv_cli(["-t", tmpl_file, "-s", "42"], input: "inner_payload")
      code.should eq(0)
      stdout.should start_with("BEGIN_WRAPPER\n")
      stdout.should end_with("\nEND_WRAPPER")
    end

    it "combines template wrapping with terminal hex diff (-d)" do
      code, stdout, _ = run_adv_cli(["-t", "PRE[%f]POST", "-d", "-s", "42"], input: "TEST_DIFF")
      code.should eq(0)
      stdout.should contain("=== Crowbar Hex Diff ===")
    end
  end

  describe "Deduplication and Uniqueness Filtering (-u, -C)" do
    it "guarantees mutually unique outputs in multi-iteration generation" do
      code, stdout, _ = run_adv_cli(["-n", "10", "-u", "-s", "1234"], input: "seed input buffer text")
      code.should eq(0)
      stdout.should_not be_empty
    end

    it "accepts custom uniqueness capacity (-C)" do
      code, stdout, _ = run_adv_cli(["-n", "5", "-u", "-C", "500", "-s", "42"], input: "capacity test")
      code.should eq(0)
      stdout.should_not be_empty
    end
  end

  describe "Deterministic Seek Offset (-S / --seek)" do
    it "produces distinct outputs with and without seek offset" do
      input = "Seek offset test buffer content"
      code1, out1, _ = run_adv_cli(["-s", "42"], input: input)
      code2, out2, _ = run_adv_cli(["-s", "42", "-S", "50"], input: input)

      code1.should eq(0)
      code2.should eq(0)
      out1.should_not eq(out2)
    end

    it "produces identical outputs when run with identical seed and seek offset" do
      input = "Reproducible seek offset test"
      code1, out1, _ = run_adv_cli(["-s", "99", "--seek", "25"], input: input)
      code2, out2, _ = run_adv_cli(["-s", "99", "--seek", "25"], input: input)

      code1.should eq(0)
      code2.should eq(0)
      out1.should eq(out2)
    end
  end

  describe "Auto-Detection Across Diverse Formats (--auto)" do
    it "auto-detects and preserves WAV audio headers" do
      # 44-byte standard RIFF WAVE header
      wav_bytes = Bytes[
        0x52, 0x49, 0x46, 0x46, # "RIFF"
        0x24, 0x00, 0x00, 0x00, # size 36
        0x57, 0x41, 0x56, 0x45, # "WAVE"
        0x66, 0x6D, 0x74, 0x20, # "fmt "
        0x10, 0x00, 0x00, 0x00, # subchunk1 size 16
        0x01, 0x00, 0x01, 0x00, # PCM, 1 channel
        0x44, 0xAC, 0x00, 0x00, # 44100 sample rate
        0x88, 0x58, 0x01, 0x00, # byte rate
        0x02, 0x00, 0x10, 0x00, # block align, 16 bits
        0x64, 0x61, 0x74, 0x61, # "data"
        0x00, 0x00, 0x00, 0x00, # data size
      ]
      code, stdout, _ = run_adv_cli(["--auto", "-s", "42"], input: String.new(wav_bytes))
      code.should eq(0)
      stdout.starts_with?("RIFF").should be_true
      stdout[8, 4].should eq("WAVE")
    end

    it "auto-detects and preserves BMP image headers" do
      bmp_bytes = Bytes[
        0x42, 0x4D,                         # "BM"
        0x36, 0x00, 0x00, 0x00,             # size
        0x00, 0x00, 0x00, 0x00,             # reserved
        0x36, 0x00, 0x00, 0x00,             # offset 54
        0x28, 0x00, 0x00, 0x00,             # header size 40
        0x01, 0x00, 0x00, 0x00,             # width 1
        0x01, 0x00, 0x00, 0x00,             # height 1
        0x01, 0x00, 0x18, 0x00,             # planes 1, bpp 24
        0x00, 0x00, 0x00, 0x00,             # compression
        0x00, 0x00, 0x00, 0x00,             # image size
        0x12, 0x0B, 0x00, 0x00, 0x12, 0x0B, # resolution
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0x00, 0x00, 0x00, # pixel data
      ]
      code, stdout, _ = run_adv_cli(["--auto", "-s", "42"], input: String.new(bmp_bytes))
      code.should eq(0)
      stdout.starts_with?("BM").should be_true
    end

    it "auto-detects and preserves MP3 ID3v2 headers" do
      mp3_bytes = Bytes[
        0x49, 0x44, 0x33,       # "ID3"
        0x03, 0x00,             # version 2.3
        0x00,                   # flags
        0x00, 0x00, 0x00, 0x0A, # synchsafe size 10
        0x54, 0x49, 0x54, 0x32, # "TIT2"
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00,
      ]
      code, stdout, _ = run_adv_cli(["--auto", "-s", "42"], input: String.new(mp3_bytes))
      code.should eq(0)
      stdout.starts_with?("ID3").should be_true
    end

    it "falls back to generic mutation when format is unrecognized" do
      raw_in = "Random opaque binary or plaintext stream without magic numbers"
      code, stdout, _ = run_adv_cli(["--auto", "-s", "42"], input: raw_in)
      code.should eq(0)
      stdout.should_not be_empty
      stdout.should_not eq(raw_in)
    end
  end

  describe "Flag Ordering & Invalid Options" do
    it "handles flags specified after sample file name" do
      f = File.join(test_tmp_dir, "trailing_flags.txt")
      File.write(f, "Sample for trailing flags test")

      code, stdout, _ = run_adv_cli([f, "-s", "55", "-p", "once"])
      code.should eq(0)
      stdout.should_not eq("Sample for trailing flags test")
    end

    it "reports error when rule name is unknown" do
      code, _, stderr = run_adv_cli(["--rule", "nonexistent_format_rule", "-s", "42"], input: "hello")
      code.should eq(1)
      stderr.should contain("Error: Unknown rule or format 'nonexistent_format_rule'")
    end

    it "reports error when format alias is unknown" do
      code, _, stderr = run_adv_cli(["-f", "unknown_format", "-s", "42"], input: "hello")
      code.should eq(1)
      stderr.should contain("Error: Unknown rule or format 'unknown_format'")
    end
  end
end
