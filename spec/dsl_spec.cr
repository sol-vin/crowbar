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

  it "configures field and character class scopes in DSL" do
    fuzzer = Crowbar.define do
      seed 12345_u64

      scope :column_two, field: 1, delimiter: ',' do
        mutate :num, :scale
      end
    end

    csv = "1,100,admin\n2,200,guest\n"
    result = fuzzer.fuzz(csv).to_s
    result.should_not eq(csv)
  end

  it "configures format preservation in DSL" do
    fuzzer = Crowbar.define do
      seed 54321_u64
      preserve :csv
    end

    csv = "col1,col2\nval1,val2\n"
    result = fuzzer.fuzz(csv).to_s
    parsed = CSV.parse(result)
    parsed.size.should be >= 1
  end

  it "configures scoped structure preservation (preserving JSON in body)" do
    fuzzer = Crowbar.define do
      seed 42_u64
      pattern :burst

      scope :body, bytes: 4.. do
        preserve :json
      end
    end

    prefix = "HDR:"
    json_part = %({"status":"ok","code":200})
    packet = prefix + json_part

    mutant = fuzzer.fuzz(packet).to_s
    mutant.should start_with("HDR:") # Prefix untouched
    mutated_json = mutant[4..]
    parsed = JSON.parse(mutated_json)
    parsed.should be_a(JSON::Any)
  end

  it "configures genetic evolution settings via DSL evolution block" do
    fuzzer = Crowbar.define do
      seed 777_u64

      evolution do
        enabled true
        population_size 32
        selection :tournament, size: 5
        exploration_rate 0.20
        crossover_rate 0.35
        stagnation_limit 50
      end
    end

    evo = fuzzer.evolution
    evo.enabled.should be_true
    evo.corpus.max_size.should eq(32)
    evo.selection_strategy.should eq(:tournament)
    evo.tournament_size.should eq(5)
    evo.exploration_rate.should eq(0.20)
    evo.crossover_rate.should eq(0.35)
    evo.stagnation_limit.should eq(50)

    # Test feedback reporting through engine
    fuzzer.report("candidate_high_score", 100.0)
    fuzzer.report("candidate_boolean", true)
    evo.corpus.size.should be >= 2
  end

  it "configures scope with combined selectors" do
    fuzzer = Crowbar.define do
      seed 1337_u64

      selector = Crowbar::Selectors::DelimitedField.new(1, ',') &
                 Crowbar::Selectors::CharacterClass.new(:digits)

      scope :numeric_column, selector do
        mutate :byte_flip
      end
    end

    csv = "user,12345,active\n"
    mutant = fuzzer.fuzz(csv).to_s
    mutant.should_not eq(csv)
  end
end
