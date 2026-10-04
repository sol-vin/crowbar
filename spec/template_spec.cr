require "./spec_helper"

describe Crowbar::Template do
  it "replaces %f with payload" do
    payload = Crowbar::Buffer.new("FUZZ_DATA")
    rendered = Crowbar::Template.render("<html><body>%f</body></html>", payload)
    rendered.to_s.should eq("<html><body>FUZZ_DATA</body></html>")
  end

  it "replaces {{data}} with payload" do
    payload = Crowbar::Buffer.new("JSON_PAYLOAD")
    rendered = Crowbar::Template.render("{\"envelope\": {{data}}}", payload)
    rendered.to_s.should eq("{\"envelope\": JSON_PAYLOAD}")
  end

  it "appends payload when no placeholder is found" do
    payload = Crowbar::Buffer.new("BODY")
    rendered = Crowbar::Template.render("PREFIX:", payload)
    rendered.to_s.should eq("PREFIX:BODY")
  end

  it "is safe with non-UTF8 binary data" do
    binary_payload = Crowbar::Buffer.new(Bytes[0x00, 0xFF, 0xFE, 0x01])
    rendered = Crowbar::Template.render("BIN:%f:END", binary_payload)
    rendered.to_slice[0, 4].should eq("BIN:".to_slice)
    rendered.to_slice[4, 4].should eq(Bytes[0x00, 0xFF, 0xFE, 0x01])
    rendered.to_slice[8, 4].should eq(":END".to_slice)
  end

  it "reads template from file if file exists" do
    tmp_path = File.join(Dir.tempdir, "crowbar_test_template_#{Random.rand(10000)}.tmpl")
    File.write(tmp_path, "HEADER\n%f\nTRAILER")
    begin
      payload = Crowbar::Buffer.new("CONTENT")
      rendered = Crowbar::Template.render(tmp_path, payload)
      rendered.to_s.should eq("HEADER\nCONTENT\nTRAILER")
    ensure
      File.delete(tmp_path) if File.exists?(tmp_path)
    end
  end
end
