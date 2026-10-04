require "./spec_helper"

describe "Multi-Feature Coverage Bucketing & Dynamic Vocabulary Harvesting" do
  it "preserves candidates that discover novel features or coverage hashes" do
    corpus = Crowbar::Evolution::Corpus.new(max_size: 2)

    # 2 high fitness candidates
    c1 = Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("seed1"), fitness: 100.0)
    c2 = Crowbar::Evolution::Candidate.new(Crowbar::Buffer.new("seed2"), fitness: 90.0)
    corpus.add(c1)
    corpus.add(c2)
    corpus.size.should eq(2)

    # Lower fitness candidate but with a novel error feature
    c3 = Crowbar::Evolution::Candidate.new(
      Crowbar::Buffer.new("novel_error_seed"),
      fitness: 10.0,
      feature: "ERR_UNEXPECTED_EOF"
    )
    is_novel = corpus.add(c3)
    is_novel.should be_true

    # The novel candidate is preserved in feature_buckets even if candidates array is trimmed
    corpus.has_feature?("ERR_UNEXPECTED_EOF").should be_true
    corpus.all_unique_candidates.map(&.buffer.to_s).should contain("novel_error_seed")

    # Lower fitness candidate with novel coverage hash
    c4 = Crowbar::Evolution::Candidate.new(
      Crowbar::Buffer.new("novel_branch_seed"),
      fitness: 15.0,
      coverage_hash: 0xAABBCCDD_u64
    )
    corpus.add(c4)
    corpus.has_coverage_hash?(0xAABBCCDD_u64).should be_true
    corpus.all_unique_candidates.map(&.buffer.to_s).should contain("novel_branch_seed")
  end

  it "harvests diagnostic tokens from error messages into mutation vocabulary" do
    fuzzer = Crowbar.define do
      seed 42_u64
    end

    error_msg = "ParserException: Unexpected token 'AUTHORIZATION_BEARER' at offset 0x00FF near identifier target_device_id"
    harvested = fuzzer.harvest(error_msg)

    harvested.should contain("AUTHORIZATION_BEARER")
    harvested.should contain("0x00FF")
    harvested.should contain("target_device_id")

    # Check that DictionaryMutator received the harvested tokens
    dict_mutator = fuzzer.pool.find?("dict").as(Crowbar::Mutators::DictionaryMutator)
    dict_mutator.tokens.should contain("AUTHORIZATION_BEARER")
    dict_mutator.tokens.should contain("0x00FF")
  end
end
