require "./spec_helper"
require "../src/crowbar/rules/jwt"
require "../src/crowbar/rules/registry"
require "../src/crowbar/rules/detector"

describe Crowbar::Rules::JWTRule do
  it "is registered in Registry and Detector" do
    Crowbar::RuleRegistry.exists?("jwt").should be_true
    Crowbar::RuleRegistry.exists?("jsonwebtoken").should be_true
    rule = Crowbar::RuleRegistry.create!("jwt")
    rule.should be_a(Crowbar::Rules::JWTRule)
  end

  it "matches valid JWT tokens and rejects non-tokens" do
    rule = Crowbar::Rules::JWTRule.new

    # Header: {"alg":"HS256","typ":"JWT"}, Payload: {"sub":"1234567890","name":"John Doe","admin":true}
    valid_jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ"
    buffer = Crowbar::Buffer.new(valid_jwt)

    rule.match?(buffer).should be_true
    Crowbar::Detector.detect(buffer).should eq(:jwt)

    invalid_token = Crowbar::Buffer.new("not.a.jwt")
    rule.match?(invalid_token).should be_false

    invalid_dots = Crowbar::Buffer.new("eyJhbGciOiJIUzI1NiJ9.onlyonedot")
    rule.match?(invalid_dots).should be_false
  end

  it "preserves three-segment structure and base64url encoding while mutating claims or header" do
    engine = Crowbar::Engine.new(1337_u64)
    rule = Crowbar::Rules::JWTRule.new
    engine.add_rule(rule)

    valid_jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ"
    buffer = Crowbar::Buffer.new(valid_jwt)

    mutated = engine.transform(buffer)
    mutated_str = mutated.to_s.strip

    mutated_str.should_not eq(valid_jwt)
    parts = mutated_str.split('.')
    parts.size.should eq(3)

    # Verify both header and payload decode to valid JSON
    hdr_json = Base64.decode_string(parts[0])
    hdr = JSON.parse(hdr_json)
    hdr.as_h?.should_not be_nil

    pld_json = Base64.decode_string(parts[1])
    pld = JSON.parse(pld_json)
    pld.as_h?.should_not be_nil
  end

  it "supports algorithm confusion mutations" do
    rule = Crowbar::Rules::JWTRule.new
    found_alg_mutation = false

    100.times do |seed|
      context = Crowbar::Context.new(seed.to_u64)
      valid_jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiZXhwIjoxNTE2MjM5MDIyfQ.c2lnbmF0dXJl"
      buf = Crowbar::Buffer.new(valid_jwt)

      rule.apply(context, buf)
      parts = buf.to_s.strip.split('.')
      hdr = JSON.parse(Base64.decode_string(parts[0])).as_h

      if hdr["alg"]? && hdr["alg"].as_s? != "HS256"
        found_alg_mutation = true
        break
      end
    end

    found_alg_mutation.should be_true
  end
end
