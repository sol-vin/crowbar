require "./spec_helper"

describe Crowbar do
  it "reports a valid semver version string" do
    Crowbar.version.should_not be_empty
    Crowbar.version.should match(/^\d+\.\d+\.\d+/)
  end

  it "provides zero-config fuzzing out of the box" do
    data = "test string 12345"
    mutant = Crowbar.fuzz(data, seed: 123_u64)
    mutant.should_not be_empty
  end
end
