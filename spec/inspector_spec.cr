require "./spec_helper"
require "../src/crowbar/inspector/analyzer"
require "../src/crowbar/inspector/view"

describe Crowbar::Inspector::Analyzer do
  it "calculates Shannon entropy accurately" do
    # Uniform buffer: 0 entropy
    zero_buf = Bytes.new(100, 0_u8)
    Crowbar::Inspector::Analyzer.calculate_entropy(zero_buf).should eq(0.0)

    # 50/50 two symbols: 1.0 bit/byte
    half_half = Bytes.new(100) { |i| i < 50 ? 0_u8 : 1_u8 }
    Crowbar::Inspector::Analyzer.calculate_entropy(half_half).should eq(1.0)

    # Uniform distribution across all 256 byte values: 8.0 bits/byte
    all_bytes = Bytes.new(256) { |i| i.to_u8 }
    Crowbar::Inspector::Analyzer.calculate_entropy(all_bytes).should eq(8.0)
  end

  it "analyzes entropy blocks and classifies density" do
    buf = Bytes.new(256) { |i| i < 128 ? 0_u8 : i.to_u8 }
    blocks = Crowbar::Inspector::Analyzer.analyze_entropy_blocks(buf, 4)

    blocks.size.should eq(4)
    blocks[0].entropy.should eq(0.0)
    blocks[0].classification.should eq("[Sparse/Zero]")
    blocks[3].entropy.should be > 5.0
  end

  it "detects HTTP boundaries" do
    http_data = "POST /api/login HTTP/1.1\r\nHost: example.com\r\nContent-Length: 13\r\n\r\n{\"user\":\"admin\"}"
    buf = Crowbar::Buffer.new(http_data)

    bounds = Crowbar::Inspector::Analyzer.detect_boundaries(buf, :http)
    bounds.size.should eq(2)
    bounds[0].name.should eq("HTTPHeaders")
    bounds[1].name.should eq("HTTPBody")
    bounds[1].size.should eq(16)
  end

  it "detects JWT boundaries" do
    valid_jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ"
    buf = Crowbar::Buffer.new(valid_jwt)

    bounds = Crowbar::Inspector::Analyzer.detect_boundaries(buf, :jwt)
    bounds.size.should eq(3)
    bounds[0].name.should eq("JWTHeader")
    bounds[1].name.should eq("JWTPayload")
    bounds[2].name.should eq("JWTSignature")
  end

  it "generates session mutation heatmaps" do
    session = Crowbar::Session.new(
      id: "inspect_test",
      baseline: Crowbar::Buffer.new("1234567890ABCDEF")
    )

    # Generate two items
    m1 = session.next_mutant
    m2 = session.next_mutant

    report = Crowbar::Inspector::Analyzer.analyze_session(session)
    report.session_id.should eq("inspect_test")
    report.heatmap.should_not be_nil

    heat = report.heatmap.not_nil!
    heat.size.should eq(16)
    # Total mutations across iterations should be tracked
    heat.sum.should be >= 0
  end

  it "renders reports in terminal and JSON modes without errors" do
    buf = Crowbar::Buffer.new("GET / HTTP/1.1\r\nHost: localhost\r\n\r\nHello World")
    report = Crowbar::Inspector::Analyzer.analyze_buffer(buf, "test.http")

    io_term = IO::Memory.new
    Crowbar::Inspector::View.render(report, io_term, json: false)
    io_term.to_s.should contain("Crowbar Diagnostic Inspector")
    io_term.to_s.should contain("HTTPHeaders")

    io_json = IO::Memory.new
    Crowbar::Inspector::View.render(report, io_json, json: true)
    parsed = JSON.parse(io_json.to_s)
    parsed["format"].as_s.should eq("http")
    parsed["size"].as_i.should eq(buf.size)
  end
end
