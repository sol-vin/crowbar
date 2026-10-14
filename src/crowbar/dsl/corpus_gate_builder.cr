require "../core/corpus_runner"
require "./builder"

module Crowbar::DSL
  # Tier 2 Declarative Builder for configuring and running a Crowbar.corpus_gate
  # inside `crystal spec` under a 60-second watchdog budget.
  class CorpusGateBuilder
    getter runner : Core::CorpusRunner
    property assert_clean : Bool

    def initialize(
      name : String = "Corpus Regression Gate",
      @assert_clean : Bool = true,
    )
      @runner = Core::CorpusRunner.new(name: name)
    end

    def name(val : String)
      @runner.name = val
    end

    # Sets the base deterministic PRNG seed
    def seed(val : UInt64 | Int32 | Int64)
      @runner.base_seed = val.to_u64
    end

    # Registers explicit PRNG seeds for deterministic mutation replay
    def seeds(*vals : UInt64 | Int32 | Int64)
      vals.each { |v| @runner.add_deterministic_seed(v.to_u64) }
    end

    def seeds(vals : Enumerable(UInt64 | Int32 | Int64))
      vals.each { |v| @runner.add_deterministic_seed(v.to_u64) }
    end

    # Number of deterministic mutation iterations across the corpus
    def iterations(count : Int32)
      @runner.iterations = count
    end

    # Number of deterministic mutations executed per corpus seed entry
    def mutations_per_seed(count : Int32)
      @runner.mutations_per_seed = count
    end

    # Adds a deterministic seed / crash reproducer payload to the corpus
    def corpus(
      payload : Buffer | Bytes | String,
      id : String? = nil,
      seed : UInt64? = nil,
      mutations : Int32 = 0,
      replay_verbatim : Bool = true,
    ) : Core::CorpusSeed
      @runner.add_seed(
        payload: payload,
        id: id,
        seed: seed,
        mutations: mutations,
        replay_verbatim: replay_verbatim
      )
    end

    def corpora(*items : Buffer | Bytes | String)
      items.each { |item| corpus(item) }
    end

    def sample(payload : Buffer | Bytes | String, id : String? = nil) : Core::CorpusSeed
      corpus(payload, id: id)
    end

    def samples(*items : Buffer | Bytes | String)
      items.each { |item| sample(item) }
    end

    def input(payload : Buffer | Bytes | String, id : String? = nil) : Core::CorpusSeed
      corpus(payload, id: id)
    end

    def inputs(*items : Buffer | Bytes | String)
      items.each { |item| input(item) }
    end

    # Registers a crash reproducer payload for verbatim regression replay
    def reproducer(
      payload : Buffer | Bytes | String,
      id : String? = nil,
      seed : UInt64? = nil,
    ) : Core::CorpusSeed
      @runner.add_seed(
        payload: payload,
        id: id || "reproducer_#{@runner.seeds.size + 1}",
        seed: seed,
        mutations: 0,
        replay_verbatim: true
      )
    end

    # Registers a Base64-encoded crash reproducer for verbatim regression replay
    def reproducer_base64(b64 : String, id : String? = nil, seed : UInt64? = nil) : Core::CorpusSeed
      @runner.add_base64_seed(b64, id: id, seed: seed)
    end

    def base64_seed(b64 : String, id : String? = nil, seed : UInt64? = nil) : Core::CorpusSeed
      @runner.add_base64_seed(b64, id: id, seed: seed)
    end

    # Registers a hex-encoded crash reproducer for verbatim regression replay
    def reproducer_hex(hex : String, id : String? = nil, seed : UInt64? = nil) : Core::CorpusSeed
      @runner.add_hex_seed(hex, id: id, seed: seed)
    end

    def hex_seed(hex : String, id : String? = nil, seed : UInt64? = nil) : Core::CorpusSeed
      @runner.add_hex_seed(hex, id: id, seed: seed)
    end

    # Registers a deterministic (seed, input) mutation replay pair
    def replay(
      seed_val : UInt64 | Int32 | Int64,
      payload : Buffer | Bytes | String,
      id : String? = nil,
      mutations : Int32 = 1,
    ) : Core::CorpusSeed
      @runner.add_replay(seed_val.to_u64, payload, id: id, mutations: mutations)
    end

    # Loads all matching seed files from a corpus directory (sorted deterministically)
    def corpus_dir(dir_path : String, pattern : String = "*") : Int32
      @runner.load_directory(dir_path, pattern)
    end

    def from_directory(dir_path : String, pattern : String = "*") : Int32
      @runner.load_directory(dir_path, pattern)
    end

    # Imports corpus candidates and recorded items from a Crowbar::Session
    def from_session(session : Session) : Int32
      @runner.load_session(session)
    end

    def from_session(session_id : String, dir : String = Session.default_dir) : Int32
      if sess = Session.load(session_id, dir)
        @runner.load_session(sess)
      else
        0
      end
    end

    # Imports crash records from a CampaignReport
    def from_report(report : Campaign::CampaignReport) : Int32
      report.crashes.each { |c| @runner.add_crash_record(c) }
      report.crashes.size
    end

    # Attaches a structure-preserving format rule
    def rule(format : Symbol) : Rule?
      r = create_rule(format)
      @runner.add_rule(r) if r
      r
    end

    def rule(instance : Rule) : Rule
      @runner.add_rule(instance)
      instance
    end

    def preserve(format : Symbol) : Rule?
      rule(format)
    end

    def preserve(format : Symbol, &block : Rule -> Nil) : Rule?
      r = create_rule(format)
      if r
        block.call(r)
        @runner.add_rule(r)
      end
      r
    end

    # Configures mutation pattern (:once, :many, :burst)
    def pattern(name : Symbol)
      @runner.pattern = case name
                        when :once, :od  then Patterns::Once.new
                        when :burst, :bu then Patterns::Burst.new
                        else                  Patterns::Many.new
                        end
    end

    # Defines a scoped mutation region
    def scope(name : String | Symbol, selector : Selector, &)
      sc = Scope.new(name.to_s, selector)
      builder = ScopeBuilder.new(sc)
      with builder yield builder
      @runner.add_scope(sc)
    end

    def scope(name : String | Symbol, bytes range : Range(B, E), &) forall B, E
      scope(name, Selectors::ByteRange.new(range)) do |b|
        with b yield b
      end
    end

    def scope(name : String | Symbol, header length : Int32, &)
      scope(name, Selectors::Header.new(length)) do |b|
        with b yield b
      end
    end

    def scope(name : String | Symbol, footer length : Int32, &)
      scope(name, Selectors::Footer.new(length)) do |b|
        with b yield b
      end
    end

    # Registers a post-mutation fixup callback
    def fixup(&block : Buffer -> Nil)
      @runner.add_fixup(&block)
    end

    # Declares expected non-fatal exception classes
    def expected_error(err_class : Exception.class)
      @runner.add_expected_error(err_class)
    end

    def expected_errors(*classes : Exception.class)
      classes.each { |c| expected_error(c) }
    end

    def allow_errors(*classes : Exception.class)
      classes.each { |c| expected_error(c) }
    end

    # Declares explicitly forbidden exception classes that always trigger a regression failure
    def reject_error(err_class : Exception.class)
      @runner.add_forbidden_error(err_class)
    end

    def forbidden_errors(*classes : Exception.class)
      classes.each { |c| reject_error(c) }
    end

    # Sets the overall watchdog budget (strictly <= 60 seconds)
    def watchdog_budget(span : Time::Span)
      @runner.watchdog_budget = span
    end

    def watchdog_budget(seconds : Int32 | Float64)
      @runner.watchdog_budget = seconds.seconds
    end

    def budget(span : Time::Span)
      @runner.watchdog_budget = span
    end

    def budget(seconds : Int32 | Float64)
      @runner.watchdog_budget = seconds.seconds
    end

    # Sets the periodic watchdog heartbeat emission interval
    def watchdog_interval(span : Time::Span)
      @runner.watchdog_interval = span
    end

    def watchdog_interval(seconds : Int32 | Float64)
      @runner.watchdog_interval = seconds.seconds
    end

    def watchdog(span : Time::Span)
      if span <= 60.seconds
        @runner.watchdog_budget = span
      end
      @runner.watchdog_interval = span
    end

    def watchdog(seconds : Int32 | Float64)
      watchdog(seconds.seconds)
    end

    # Sets the per-seed execution timeout
    def timeout(span : Time::Span)
      @runner.per_seed_timeout = span
    end

    def timeout(ms : Int32)
      @runner.per_seed_timeout = ms.milliseconds
    end

    def per_seed_timeout(span : Time::Span)
      @runner.per_seed_timeout = span
    end

    def auto_shrink(val : Bool)
      @runner.auto_shrink = val
    end

    def fail_fast(val : Bool)
      @runner.fail_fast = val
    end

    def verify_determinism(val : Bool = true)
      @runner.verify_determinism = val
    end

    def assert_clean(val : Bool = true)
      @assert_clean = val
    end

    def raise_on_failure(val : Bool = true)
      @assert_clean = val
    end

    # Registers the primary target execution block under test
    def execute(&block : Buffer -> Nil)
      @runner.execution = block
    end

    def target(&block : Buffer -> Nil)
      @runner.execution = block
    end

    # Registers a boolean regression invariant that must hold for every seed/mutant
    def assert_invariant(name : String = "invariant_#{@runner.invariants.size + 1}", &block : Buffer -> Bool)
      @runner.add_invariant(name, &block)
    end

    def invariant(name : String = "invariant_#{@runner.invariants.size + 1}", &block : Buffer -> Bool)
      @runner.add_invariant(name, &block)
    end

    # Registers an assertion block (e.g. containing Crystal `spec` `.should` expectations)
    def assert(name : String = "assertion_#{@runner.assertions.size + 1}", &block : Buffer -> Nil)
      @runner.add_assertion(name, &block)
    end

    def assert_each(name : String = "assertion_#{@runner.assertions.size + 1}", &block : Buffer -> Nil)
      @runner.add_assertion(name, &block)
    end

    def on_heartbeat(&block : Int32, Float64 -> Nil)
      @runner.on_heartbeat = block
    end

    def on_seed_complete(&block : Core::SeedResult -> Nil)
      @runner.on_seed_complete = block
    end

    def on_regression(&block : Core::SeedResult -> Nil)
      @runner.on_regression = block
    end

    def build : Core::CorpusRunner
      @runner
    end

    def run : Core::CorpusGateReport
      report = @runner.run
      report.assert_clean! if @assert_clean
      report
    end

    private def create_rule(format : Symbol) : Rule?
      case format
      when :json                        then Rules::JSONRule.new
      when :yaml, :yml                  then Rules::YAMLRule.new
      when :jwt                         then Rules::JWTRule.new
      when :http                        then Rules::HTTPRule.new
      when :dns                         then Rules::DNSRule.new
      when :csv, :tsv                   then Rules::CSVRule.new
      when :xml, :html                  then Rules::XMLRule.new
      when :url, :uri                   then Rules::URLRule.new
      when :tlv                         then Rules::TLVRule.new
      when :base64, :b64                then Rules::Base64Rule.new
      when :varint, :leb128             then Rules::VarintRule.new
      when :ftp                         then Rules::FTPRule.new
      when :sql                         then Rules::SQLRule.new
      when :png                         then Rules::PNGRule.new
      when :bmp                         then Rules::BMPRule.new
      when :wav                         then Rules::WAVRule.new
      when :mp3                         then Rules::MP3Rule.new
      when :wad                         then Rules::WADRule.new
      when :pdf                         then Rules::PDFRule.new
      when :seven_zip, :sevenzip, :"7z" then Rules::SevenZipRule.new
      when :tar, :ustar                 then Rules::TarRule.new
      when :zip, :pkzip                 then Rules::ZipRule.new
      when :packet, :ipv4, :pcap        then Rules::PacketRule.new
      when :markdown, :md               then Rules::MarkdownRule.new
      else                                   nil
      end
    end
  end
end

module Crowbar
  # Declarative DSL entry point for executing a deterministic seed replay and
  # regression assertion gate inside `crystal spec` under a 60s watchdog budget.
  def self.corpus_gate(
    name : String = "Corpus Regression Gate",
    assert_clean : Bool = true,
    &
  ) : Core::CorpusGateReport
    builder = DSL::CorpusGateBuilder.new(name, assert_clean: assert_clean)
    with builder yield builder
    builder.run
  end

  # Strictly executes a corpus regression gate and always raises RegressionError on failure
  def self.corpus_gate!(name : String = "Corpus Regression Gate", &) : Core::CorpusGateReport
    corpus_gate(name, assert_clean: true) do |gate|
      with gate yield gate
    end
  end

  # Constructs a configured Core::CorpusRunner without immediately executing it
  def self.define_corpus_gate(name : String = "Corpus Regression Gate", &) : Core::CorpusRunner
    builder = DSL::CorpusGateBuilder.new(name)
    with builder yield builder
    builder.build
  end
end
