require "./spec_helper"

describe "Crowbar DSL & Pipeline" do
  it "Crowbar.define builds a working engine with custom seed and scopes" do
    fuzzer = Crowbar.define do
      seed 99999_u64

      pattern :many

      scope :header, bytes: 0...4 do
        weight 1.0
        mutate :byte_flip
      end

      scope :body, bytes: 4.. do
        weight 2.0
        mutate :boundary_number
      end

      fixup do |buffer|
        # Set magic byte at index 0
        buffer[0] = 0xAA_u8 if buffer.size > 0
      end
    end

    sample = "HEAD12345678"
    mutant = fuzzer.fuzz(sample)
    mutant.size.should be > 0
    mutant[0].should eq(0xAA_u8) # Verified fixup hook executed
  end

  it "match regex selector targets specific substrings" do
    fuzzer = Crowbar.define do
      seed 42_u64
      match /"([^"]+)"/, group: 1 do
        mutate :byte_random
      end
    end

    sample = %({"key": "original_value"})
    mutant = fuzzer.fuzz(sample)
    mutant.to_s.should_not eq(sample)
  end

  it "Crowbar.fuzz runs zero-config black-box transformations" do
    res = Crowbar.fuzz("hello world 12345", seed: 42_u64)
    res.should be_a(String)
    res.should_not eq("hello world 12345")
  end
end
