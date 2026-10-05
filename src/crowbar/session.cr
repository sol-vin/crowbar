require "json"
require "base64"
require "./buffer"
require "./engine"
require "./evolution/manager"

module Crowbar
  # Serializable state for a multi-armed bandit mutator arm
  struct ArmState
    include JSON::Serializable

    property pulls : Int64
    property rewards : Float64

    def initialize(@pulls : Int64 = 0_i64, @rewards : Float64 = 0.0)
    end
  end

  # Serializable state for an evolutionary corpus candidate
  struct CandidateState
    include JSON::Serializable

    property buffer_b64 : String
    property fitness : Float64
    property generation : Int64
    property mutation_history : Array(String)
    property feature : String?
    property coverage_hash : UInt64?

    def initialize(
      @buffer_b64 : String,
      @fitness : Float64 = 0.0,
      @generation : Int64 = 0_i64,
      @mutation_history : Array(String) = [] of String,
      @feature : String? = nil,
      @coverage_hash : UInt64? = nil,
    )
    end
  end

  # Serializable log entry tracking session events
  struct HistoryEntry
    include JSON::Serializable

    property iteration : Int32
    property action : String # "next", "reward", "reset"
    property value : Float64?
    property mutators : Array(String)
    property timestamp : Time

    def initialize(
      @iteration : Int32,
      @action : String,
      @mutators : Array(String) = [] of String,
      @value : Float64? = nil,
      @timestamp : Time = Time.utc,
    )
    end
  end

  # Serializable configuration for a scoped target region
  struct ScopeConfig
    include JSON::Serializable

    property name : String
    property selector_type : String # "range", "header", "footer", "delimited", "chars", "stride", "entropy", "regex"
    property params : Hash(String, String)
    property weight : Float64

    def initialize(
      @name : String,
      @selector_type : String,
      @params : Hash(String, String) = Hash(String, String).new,
      @weight : Float64 = 1.0,
    )
    end
  end

  # Persistent Session Manager for iterative fuzzing and evolutionary feedback.
  # Stores baseline input, bandit weights, genetic corpus, and mutation histories across CLI invocations.
  class Session
    include JSON::Serializable

    property id : String
    property created_at : Time
    property updated_at : Time
    property iteration : Int32
    property baseline_b64 : String
    property last_mutant_b64 : String?
    property last_mutators : Array(String)
    property last_reward : Float64?
    property rule_name : String?
    @[JSON::Field(emit_null: false)]
    property active_rules : Array(String) = [] of String
    property pattern_name : String?
    property selected_mutations : String?
    property seed : UInt64
    property total_pulls : Int64
    property arms : Hash(String, ArmState)
    property corpus_items : Array(CandidateState)
    property history : Array(HistoryEntry)
    @[JSON::Field(emit_null: false)]
    property scopes : Array(ScopeConfig) = [] of ScopeConfig
    @[JSON::Field(emit_null: false)]
    property template : String? = nil
    @[JSON::Field(emit_null: false)]
    property unique_enabled : Bool = false
    @[JSON::Field(emit_null: false)]
    property uniqueness_capacity : Int32 = 10_000
    @[JSON::Field(emit_null: false)]
    property seen_hashes : Array(UInt64) = [] of UInt64
    @[JSON::Field(emit_null: false)]
    property seek_offset : Int64 = 0_i64
    @[JSON::Field(emit_null: false)]
    property input_encoding : String? = nil
    @[JSON::Field(emit_null: false)]
    property output_encoding : String? = nil

    def initialize(
      @id : String,
      baseline : Buffer,
      @rule_name : String? = nil,
      @pattern_name : String? = nil,
      @selected_mutations : String? = nil,
      seed : UInt64? = nil,
    )
      @created_at = Time.utc
      @updated_at = Time.utc
      @iteration = 0
      @baseline_b64 = Base64.strict_encode(baseline.to_slice)
      @last_mutant_b64 = nil
      @last_mutators = [] of String
      @last_reward = nil
      @seed = seed || PRNG.default_seed
      @total_pulls = 0_i64
      @arms = Hash(String, ArmState).new
      @corpus_items = [] of CandidateState
      @history = [] of HistoryEntry
      @active_rules = [] of String
      if r = @rule_name
        @active_rules << r unless r.empty?
      end
      @scopes = [] of ScopeConfig
    end

    def self.default_dir : String
      ENV["CROWBAR_SESSION_DIR"]? || ".crowbar/sessions"
    end

    def self.session_path(id : String, dir : String = default_dir) : String
      File.join(dir, "#{id}.json")
    end

    def self.exists?(id : String, dir : String = default_dir) : Bool
      File.exists?(session_path(id, dir))
    end

    def self.load(id : String, dir : String = default_dir) : Session?
      path = session_path(id, dir)
      return nil unless File.exists?(path)
      Session.from_json(File.read(path))
    rescue
      nil
    end

    def self.load_or_create(
      id : String,
      baseline : Buffer,
      rule_name : String? = nil,
      pattern_name : String? = nil,
      selected_mutations : String? = nil,
      seed : UInt64? = nil,
      dir : String = default_dir,
    ) : Session
      if existing = load(id, dir)
        # If baseline input text changed, reset session as requested
        if existing.baseline != baseline
          existing.reset_with(baseline, rule_name, pattern_name, selected_mutations, seed)
          existing.save(dir)
        end
        existing
      else
        sess = new(id, baseline, rule_name, pattern_name, selected_mutations, seed)
        if (rule_name.nil? || rule_name.empty?)
          sess.auto_detect_rule
        end
        sess.save(dir)
        sess
      end
    end

    def self.reset(id : String, dir : String = default_dir) : Bool
      path = session_path(id, dir)
      if File.exists?(path)
        File.delete(path)
        true
      else
        false
      end
    end

    def self.list(dir : String = default_dir) : Array(String)
      return [] of String unless Dir.exists?(dir)
      Dir.children(dir)
        .select { |f| f.ends_with?(".json") }
        .map { |f| f.rchop(".json") }
        .sort
    end

    def baseline : Buffer
      Buffer.new(Base64.decode(@baseline_b64))
    end

    def baseline=(buf : Buffer)
      @baseline_b64 = Base64.strict_encode(buf.to_slice)
    end

    def last_mutant : Buffer?
      if b64 = @last_mutant_b64
        Buffer.new(Base64.decode(b64))
      else
        nil
      end
    end

    def last_mutant=(buf : Buffer?)
      @last_mutant_b64 = buf ? Base64.strict_encode(buf.to_slice) : nil
    end

    # Resets the session with a new baseline input, clearing corpus and iteration counter
    def reset_with(
      new_baseline : Buffer,
      rule_name : String? = nil,
      pattern_name : String? = nil,
      selected_mutations : String? = nil,
      seed : UInt64? = nil,
    )
      self.baseline = new_baseline
      if rule_name
        @rule_name = rule_name
        @active_rules.clear
        @active_rules << rule_name
      elsif @active_rules.empty?
        auto_detect_rule
      end
      @pattern_name = pattern_name if pattern_name
      @selected_mutations = selected_mutations if selected_mutations
      @seed = seed if seed
      @iteration = 0
      @last_mutant_b64 = nil
      @last_mutators.clear
      @last_reward = nil
      @corpus_items.clear
      @history << HistoryEntry.new(@iteration, "reset")
      @updated_at = Time.utc
    end

    # Builds and re-hydrates an Engine instance with stored session state
    def build_engine : Engine
      current_seed = @seed &+ @iteration.to_u64 &+ @seek_offset.to_u64
      engine = Engine.new(current_seed)
      engine.evolution.enabled = true
      engine.pool.bandit = engine.evolution.bandit
      engine.pool.use_bandit = true

      # Restore template configuration
      engine.template = @template if @template

      # Restore uniqueness filter
      if @unique_enabled
        filter = Evolution::UniquenessFilter.new(@uniqueness_capacity)
        filter.load_hashes(@seen_hashes)
        engine.uniqueness_filter = filter
      end

      # Restore pattern
      if pat = @pattern_name
        if p_obj = Patterns.create?(pat)
          engine.pattern = p_obj
        end
      end

      # Restore rules
      rules_to_load = @active_rules.dup
      if rules_to_load.empty? && (r = @rule_name)
        rules_to_load << r unless r.empty?
      end
      rules_to_load.each do |r|
        if rule_obj = Rules::Registry.create?(r)
          engine.add_rule(rule_obj)
        end
      end

      # Restore mutator filter
      if m_list = @selected_mutations
        names = m_list.split(",").map(&.strip)
        engine.pool.mutators.clear
        pool = MutatorPool.new
        names.each do |n|
          if m = pool.find?(n)
            engine.pool.register(m)
          end
        end
      end

      # Restore scopes
      @scopes.each do |sc_conf|
        sel : Selector? = case sc_conf.selector_type.downcase
        when "range", "byte_range", "bytes"
          s = sc_conf.params["start"]?.try(&.to_i) || 0
          e = sc_conf.params["end"]?.try(&.to_i) || 0
          Selectors::ByteRange.new(s..e, weight: sc_conf.weight)
        when "header"
          len = sc_conf.params["length"]?.try(&.to_i) || 16
          inv = sc_conf.params["invert"]? == "true"
          Selectors::Header.new(len, invert: inv, weight: sc_conf.weight)
        when "footer"
          len = sc_conf.params["length"]?.try(&.to_i) || 16
          inv = sc_conf.params["invert"]? == "true"
          Selectors::Footer.new(len, invert: inv, weight: sc_conf.weight)
        when "delimited", "field"
          idx = sc_conf.params["index"]?.try(&.to_i) || 0
          delim = (sc_conf.params["delimiter"]? || ",").byte_at(0)
          Selectors::DelimitedField.new(idx, delim, weight: sc_conf.weight)
        when "chars", "character_class"
          k_str = (sc_conf.params["kind"]? || "printable").downcase
          kind = case k_str
                 when "digits", "digit"       then Selectors::CharacterClass::Kind::Digits
                 when "hex"                   then Selectors::CharacterClass::Kind::Hex
                 when "alpha"                 then Selectors::CharacterClass::Kind::Alpha
                 when "alnum", "alphanumeric" then Selectors::CharacterClass::Kind::Alphanumeric
                 when "whitespace", "space"   then Selectors::CharacterClass::Kind::Whitespace
                 when "high", "high_bytes"    then Selectors::CharacterClass::Kind::HighBytes
                 else                              Selectors::CharacterClass::Kind::Printable
                 end
          Selectors::CharacterClass.new(kind, weight: sc_conf.weight)
        when "stride"
          step = sc_conf.params["step"]?.try(&.to_i) || 4
          off = sc_conf.params["offset"]?.try(&.to_i) || 0
          len = sc_conf.params["length"]?.try(&.to_i) || 1
          Selectors::Stride.new(step, off, len, weight: sc_conf.weight)
        when "entropy"
          m_str = (sc_conf.params["mode"]? || "high").downcase
          mode = m_str == "low" ? Selectors::Entropy::Mode::Low : Selectors::Entropy::Mode::High
          Selectors::Entropy.new(mode, weight: sc_conf.weight)
        when "regex", "match"
          pat_str = sc_conf.params["pattern"]? || ".*"
          grp = sc_conf.params["group"]?.try(&.to_i) || 0
          Selectors::Regex.new(Regex.new(pat_str), grp, weight: sc_conf.weight)
        else
          nil
        end

        if sel
          sc = Scope.new(sc_conf.name, sel, sc_conf.weight)
          if @selected_mutations
            sc.pool.mutators.clear
            engine.pool.mutators.each { |m| sc.pool.register(m) }
          end
          sc.pool.bandit = engine.evolution.bandit
          sc.pool.use_bandit = engine.evolution.enabled
          engine.add_scope(sc)
        end
      end

      # Restore Bandit arms and total pulls
      engine.evolution.bandit.total_pulls = @total_pulls
      @arms.each do |name, state|
        arm = engine.evolution.bandit.ensure_arm(name)
        arm.pulls = state.pulls
        arm.rewards = state.rewards
      end

      # Restore Corpus candidates
      @corpus_items.each do |c_state|
        cand_buf = Buffer.new(Base64.decode(c_state.buffer_b64))
        cand = Evolution::Candidate.new(
          cand_buf,
          fitness: c_state.fitness,
          generation: c_state.generation,
          mutation_history: c_state.mutation_history.dup,
          feature: c_state.feature,
          coverage_hash: c_state.coverage_hash
        )
        engine.evolution.corpus.add(cand)
        # Register as secondary sample for sequence splicing
        engine.context.add_sample(cand_buf)
      end

      engine
    end

    # Generates the next mutant, updates session iteration, syncs bandit & corpus, and saves state.
    # Optionally accepts runtime overrides for uniqueness deduplication, PRNG seek, and output templating.
    def next_mutant(
      dir : String = Session.default_dir,
      unique : Bool? = nil,
      seek : Int64? = nil,
      template_override : String? = nil,
    ) : Buffer
      @seek_offset += seek if seek
      if t = template_override
        @template = t
      end
      effective_template = @template
      if unique == true
        @unique_enabled = true
      end

      engine = build_engine
      engine.template = effective_template if effective_template

      # Ensure uniqueness filter is attached if requested via parameter
      if unique == true && engine.uniqueness_filter.nil?
        filter = Evolution::UniquenessFilter.new(@uniqueness_capacity)
        filter.load_hashes(@seen_hashes)
        engine.uniqueness_filter = filter
      end

      mutated = engine.transform(baseline)

      @iteration += 1
      self.last_mutant = mutated
      @last_mutators = engine.evolution.last_applied_mutators.dup

      # Sync uniqueness hashes back to session
      if filter = engine.uniqueness_filter
        @seen_hashes = filter.to_a
      end

      # Sync Bandit weights back to session
      @total_pulls = engine.evolution.bandit.total_pulls
      engine.evolution.bandit.arms.each do |name, arm|
        @arms[name] = ArmState.new(arm.pulls, arm.rewards)
      end

      # Sync Corpus back to session
      @corpus_items = engine.evolution.corpus.all_unique_candidates.map do |c|
        CandidateState.new(
          Base64.strict_encode(c.buffer.to_slice),
          c.fitness,
          c.generation,
          c.mutation_history.dup,
          c.feature,
          c.coverage_hash
        )
      end

      @history << HistoryEntry.new(@iteration, "next", @last_mutators)
      @updated_at = Time.utc
      save(dir)
      mutated
    end

    # Applies feedback score (-1.0 to 1.0) to the last generated mutant and mutators
    def reward(value : Float64, dir : String = Session.default_dir) : Session
      raise ArgumentError.new("Session has no previous mutant to reward. Run 'next' first.") if @last_mutators.empty?

      # 1. Update bandit credit for the mutators that produced the last mutant
      @last_mutators.each do |mut_name|
        current_arm = @arms[mut_name]? || ArmState.new
        current_arm.rewards += value
        @arms[mut_name] = current_arm
      end

      # 2. Update corpus: positive feedback adds candidate, negative feedback prunes
      if value >= 0.0
        if mutant = last_mutant
          cand_b64 = Base64.strict_encode(mutant.to_slice)
          # Add or update candidate in corpus
          @corpus_items.reject! { |c| c.buffer_b64 == cand_b64 }
          @corpus_items << CandidateState.new(
            cand_b64,
            fitness: value,
            generation: @iteration.to_i64,
            mutation_history: @last_mutators.dup
          )
        end
      else
        if mutant = last_mutant
          cand_b64 = Base64.strict_encode(mutant.to_slice)
          @corpus_items.reject! { |c| c.buffer_b64 == cand_b64 }
        end
      end

      @last_reward = value
      @history << HistoryEntry.new(@iteration, "reward", @last_mutators, value)
      @updated_at = Time.utc
      save(dir)
      self
    end

    # Serializes session to JSON file on disk
    def save(dir : String = Session.default_dir)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      path = Session.session_path(@id, dir)
      File.write(path, self.to_pretty_json)
    end

    # Setup & Configuration Methods

    def add_rule(name : String) : self
      rule_clean = name.strip.downcase
      unless @active_rules.includes?(rule_clean)
        @active_rules << rule_clean
      end
      @rule_name = @active_rules.first?
      @updated_at = Time.utc
      self
    end

    def remove_rule(name : String) : self
      rule_clean = name.strip.downcase
      @active_rules.reject! { |r| r == rule_clean }
      @rule_name = @active_rules.first?
      @updated_at = Time.utc
      self
    end

    def clear_rules : self
      @active_rules.clear
      @rule_name = nil
      @updated_at = Time.utc
      self
    end

    def auto_detect_rule : String?
      if detected = Detector.detect(baseline)
        rule_str = detected.to_s
        add_rule(rule_str)
        rule_str
      else
        nil
      end
    end

    def add_mutator(name : String) : self
      current = (@selected_mutations || "").split(",").map(&.strip).reject(&.empty?)
      clean = name.strip
      current << clean unless current.includes?(clean)
      @selected_mutations = current.empty? ? nil : current.join(",")
      @updated_at = Time.utc
      self
    end

    def remove_mutator(name : String) : self
      if cur = @selected_mutations
        current = cur.split(",").map(&.strip).reject(&.empty?)
        clean = name.strip
        current.reject! { |m| m == clean }
        @selected_mutations = current.empty? ? nil : current.join(",")
        @updated_at = Time.utc
      end
      self
    end

    def set_mutators(list : Array(String)) : self
      clean_list = list.map(&.strip).reject(&.empty?)
      @selected_mutations = clean_list.empty? ? nil : clean_list.join(",")
      @updated_at = Time.utc
      self
    end

    def reset_mutators : self
      @selected_mutations = nil
      @updated_at = Time.utc
      self
    end

    def set_pattern(pat : String) : self
      @pattern_name = pat.strip
      @updated_at = Time.utc
      self
    end

    def add_scope(name : String, selector_type : String, params : Hash(String, String) = Hash(String, String).new, weight : Float64 = 1.0) : self
      @scopes.reject! { |s| s.name == name }
      @scopes << ScopeConfig.new(name, selector_type, params, weight)
      @updated_at = Time.utc
      self
    end

    def remove_scope(name : String) : self
      @scopes.reject! { |s| s.name == name }
      @updated_at = Time.utc
      self
    end

    def clear_scopes : self
      @scopes.clear
      @updated_at = Time.utc
      self
    end

    def set_template(spec : String?) : self
      @template = spec.nil? || spec.empty? ? nil : spec
      @updated_at = Time.utc
      self
    end

    def set_unique(enabled : Bool, capacity : Int32 = 10_000) : self
      @unique_enabled = enabled
      @uniqueness_capacity = capacity
      @updated_at = Time.utc
      self
    end

    def set_seek(offset : Int64) : self
      @seek_offset = offset
      @updated_at = Time.utc
      self
    end

    def clear_seen_hashes : self
      @seen_hashes.clear
      @updated_at = Time.utc
      self
    end
  end
end
