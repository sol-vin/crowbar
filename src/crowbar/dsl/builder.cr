require "../engine"

module Crowbar
  # DSL Builder for configuring Scopes, Selectors, and Mutators
  class ScopeBuilder
    getter scope : Scope

    def initialize(@scope : Scope)
      @cleared_defaults = false
    end

    def weight(val : Float64)
      @scope.weight = val
    end

    private def create_rule(format : Symbol) : Rule?
      case format
      when :json                        then Rules::JSONRule.new
      when :yaml, :yml                  then Rules::YAMLRule.new
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

    # Enable structure-preserving rules within this scope
    def preserve(format : Symbol)
      rule = create_rule(format)
      @scope.add_rule(rule) if rule
      rule
    end

    def preserve(format : Symbol, &block : Rule -> Nil)
      rule = create_rule(format)
      if rule
        block.call(rule)
        @scope.add_rule(rule)
      end
      rule
    end

    def http(&)
      rule = Rules::HTTPRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def ftp(&)
      rule = Rules::FTPRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def sql(&)
      rule = Rules::SQLRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def png(&)
      rule = Rules::PNGRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def bmp(&)
      rule = Rules::BMPRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def wav(&)
      rule = Rules::WAVRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def mp3(&)
      rule = Rules::MP3Rule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def wad(&)
      rule = Rules::WADRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def pdf(&)
      rule = Rules::PDFRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def seven_zip(&)
      rule = Rules::SevenZipRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def tar(&)
      rule = Rules::TarRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def zip(&)
      rule = Rules::ZipRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def packet(&)
      rule = Rules::PacketRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def markdown(&)
      rule = Rules::MarkdownRule.new
      with rule yield rule
      @scope.add_rule(rule)
      rule
    end

    def preserve_format(format : Symbol)
      preserve(format)
    end

    def preserve_format(format : Symbol, &)
      preserve(format) { |r| with r yield r }
    end

    # Attach mutators by name
    def mutate(*names : Symbol)
      unless @cleared_defaults
        @scope.pool.mutators.clear
        @cleared_defaults = true
      end
      names.each do |name|
        case name
        when :byte_drop, :bd                           then @scope.pool.register(Mutators::ByteDrop.new)
        when :byte_flip, :bf                           then @scope.pool.register(Mutators::ByteFlip.new)
        when :byte_insert, :bi                         then @scope.pool.register(Mutators::ByteInsert.new)
        when :byte_repeat, :br                         then @scope.pool.register(Mutators::ByteRepeat.new)
        when :byte_permute, :bp                        then @scope.pool.register(Mutators::BytePermute.new)
        when :byte_inc_dec, :bei, :bed                 then @scope.pool.register(Mutators::ByteIncDec.new)
        when :byte_random, :ber                        then @scope.pool.register(Mutators::ByteRandom.new)
        when :bit_flip_run, :bfr                       then @scope.pool.register(Mutators::BitFlipRun.new)
        when :walking_bit, :wb                         then @scope.pool.register(Mutators::WalkingBit.new)
        when :sequence_repeat, :sr                     then @scope.pool.register(Mutators::SequenceRepeat.new)
        when :sequence_delete, :sd                     then @scope.pool.register(Mutators::SequenceDelete.new)
        when :sequence_swap, :ss                       then @scope.pool.register(Mutators::SequenceSwap.new)
        when :line_delete, :ld                         then @scope.pool.register(Mutators::LineDelete.new)
        when :line_duplicate, :lr2                     then @scope.pool.register(Mutators::LineDuplicate.new)
        when :line_swap, :ls                           then @scope.pool.register(Mutators::LineSwap.new)
        when :line_permute, :lp                        then @scope.pool.register(Mutators::LinePermute.new)
        when :tree_delete, :td                         then @scope.pool.register(Mutators::TreeDelete.new)
        when :tree_duplicate, :tr2                     then @scope.pool.register(Mutators::TreeDuplicate.new)
        when :tree_swap, :ts1                          then @scope.pool.register(Mutators::TreeSwap.new)
        when :tree_stutter, :tr                        then @scope.pool.register(Mutators::TreeStutter.new)
        when :boundary_number, :boundary_numbers, :num then @scope.pool.register(Mutators::BoundaryNumbers.new)
        when :unicode, :unicode_edge_cases, :ui        then @scope.pool.register(Mutators::UnicodeEdgeCases.new)
        when :whitespace, :delimiters, :wd             then @scope.pool.register(Mutators::WhitespaceDelimiters.new)
        when :arithmetic_scaler, :scale, :arithmetic   then @scope.pool.register(Mutators::ArithmeticScaler.new)
        when :timestamp, :time                         then @scope.pool.register(Mutators::TimestampMutator.new)
        when :case_flip, :cf                           then @scope.pool.register(Mutators::CaseFlip.new)
        when :homoglyph, :homoglyphs, :homo            then @scope.pool.register(Mutators::HomoglyphMutator.new)
        when :dictionary, :dict                        then @scope.pool.register(Mutators::DictionaryMutator.new)
        when :padding, :pad                            then @scope.pool.register(Mutators::PaddingMutator.new)
        when :truncation, :trunc                       then @scope.pool.register(Mutators::TruncationMutator.new)
        when :nesting_depth, :nest                     then @scope.pool.register(Mutators::NestingDepth.new)
        when :length_boundary, :len                    then @scope.pool.register(Mutators::LengthBoundary.new)
        when :float_anomalies, :flt                    then @scope.pool.register(Mutators::FloatAnomalies.new)
        when :delimiter_stress, :delim                 then @scope.pool.register(Mutators::DelimiterStress.new)
        when :splice, :fuse, :ft, :fn                  then @scope.pool.register(Mutators::Splice.new)
        when :security, :sec, :ab, :bad_ascii          then @scope.pool.register(Mutators::Security.new)
        else
          # Allow string lookup
          if m = @scope.pool.find?(name.to_s)
            @scope.pool.register(m)
          end
        end
      end
    end
  end

  # DSL Builder for Genetic Algorithm and Evolutionary tuning
  class EvolutionBuilder
    getter manager : Evolution::Manager
    getter engine : Engine?

    def initialize(@manager : Evolution::Manager, @engine : Engine? = nil)
    end

    def enabled(val : Bool)
      @manager.enabled = val
    end

    def population_size(val : Int32)
      @manager.corpus.max_size = val
    end

    def exploration_rate(val : Float64)
      @manager.exploration_rate = val
    end

    def crossover_rate(val : Float64)
      @manager.crossover_rate = val
    end

    def stagnation_limit(val : Int32)
      @manager.stagnation_limit = val
    end

    def selection(strategy : Symbol, size : Int32 = 4)
      @manager.selection_strategy = strategy
      @manager.tournament_size = size
    end

    # Enables UCB1 Multi-Armed Bandit credit assignment for mutators
    def use_bandit(val : Bool = true)
      if eng = @engine
        eng.pool.use_bandit = val
        eng.scopes.each { |s| s.pool.use_bandit = val }
      end
    end

    # Tunes exploration factor for UCB1 bandit (default ~1.414)
    def exploration_coeff(val : Float64)
      @manager.bandit.exploration_coeff = val
    end
  end

  # Top-level DSL Builder for Crowbar
  class Builder
    getter engine : Engine

    def initialize(seed : UInt64? = nil)
      @engine = seed ? Engine.new(seed) : Engine.new
    end

    # Set PRNG seed
    def seed(val : UInt64 | Int32 | Int64)
      @engine.seed = val.to_u64
    end

    # Configure Genetic Algorithm & Feedback
    def evolution(&)
      builder = EvolutionBuilder.new(@engine.evolution, @engine)
      with builder yield builder
    end

    # Configure mutation pattern (:once, :many, :burst)
    def pattern(name : Symbol)
      @engine.pattern = case name
                        when :once, :od  then Patterns::Once.new
                        when :burst, :bu then Patterns::Burst.new
                        else                  Patterns::Many.new
                        end
    end

    # Configure output envelope / template
    def template(spec : String)
      @engine.template = spec
    end

    # Configure deduplication uniqueness filter
    def unique(capacity : Int32 = 10_000)
      @engine.uniqueness_filter = Evolution::UniquenessFilter.new(capacity)
    end

    # Fast-forwards PRNG state by offset
    def seek(offset : Int)
      @engine.seek(offset)
    end

    # Add secondary sample for inter-sample splicing
    def add_sample(sample : Buffer | Bytes | String)
      @engine.add_sample(sample)
    end

    private def create_rule(format : Symbol) : Rule?
      case format
      when :json                        then Rules::JSONRule.new
      when :yaml, :yml                  then Rules::YAMLRule.new
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

    # Enable structure-preserving rules (:json, :yaml, :http, :dns, :csv, :xml, :url, :tlv, :base64, :varint, :ftp, :sql, :png, :bmp, :wav, :mp3, :wad, :pdf)
    def preserve(format : Symbol)
      rule = create_rule(format)
      @engine.add_rule(rule) if rule
      rule
    end

    def preserve(format : Symbol, &block : Rule -> Nil)
      rule = create_rule(format)
      if rule
        block.call(rule)
        @engine.add_rule(rule)
      end
      rule
    end

    def http(&)
      rule = Rules::HTTPRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def ftp(&)
      rule = Rules::FTPRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def sql(&)
      rule = Rules::SQLRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def png(&)
      rule = Rules::PNGRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def bmp(&)
      rule = Rules::BMPRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def wav(&)
      rule = Rules::WAVRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def mp3(&)
      rule = Rules::MP3Rule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def wad(&)
      rule = Rules::WADRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def pdf(&)
      rule = Rules::PDFRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def seven_zip(&)
      rule = Rules::SevenZipRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def tar(&)
      rule = Rules::TarRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def zip(&)
      rule = Rules::ZipRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def packet(&)
      rule = Rules::PacketRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def markdown(&)
      rule = Rules::MarkdownRule.new
      with rule yield rule
      @engine.add_rule(rule)
      rule
    end

    def preserve_format(format : Symbol)
      preserve(format)
    end

    def preserve_format(format : Symbol, &block : Rule -> Nil)
      preserve(format, &block)
    end

    # Define a scoped region with an explicit selector instance
    def scope(name : String | Symbol, selector : Selector, &)
      sc = Scope.new(name.to_s, selector)
      builder = ScopeBuilder.new(sc)
      with builder yield builder
      @engine.add_scope(sc)
    end

    # Define a scoped byte range
    def scope(name : String | Symbol, bytes range : Range(B, E), &) forall B, E
      scope(name, Selectors::ByteRange.new(range)) do |b|
        with b yield b
      end
    end

    # Define a scoped header
    def scope(name : String | Symbol, header length : Int32, &)
      scope(name, Selectors::Header.new(length)) do |b|
        with b yield b
      end
    end

    # Define a scoped footer
    def scope(name : String | Symbol, footer length : Int32, &)
      scope(name, Selectors::Footer.new(length)) do |b|
        with b yield b
      end
    end

    # Define a scoped delimited field/column
    def scope(name : String | Symbol, field index : Int32, delimiter : UInt8 | Char | String = ',', &)
      scope(name, Selectors::DelimitedField.new(index, delimiter)) do |b|
        with b yield b
      end
    end

    # Define a scoped character class
    def scope(name : String | Symbol, chars kind : Selectors::CharacterClass::Kind | Symbol, &)
      scope(name, Selectors::CharacterClass.new(kind)) do |b|
        with b yield b
      end
    end

    # Define a scoped stride / periodic pattern
    def scope(name : String | Symbol, stride step : Int32, offset : Int32 = 0, length : Int32 = 1, &)
      scope(name, Selectors::Stride.new(step, offset, length)) do |b|
        with b yield b
      end
    end

    # Define a scoped entropy target
    def scope(name : String | Symbol, entropy mode : Selectors::Entropy::Mode | Symbol, &)
      scope(name, Selectors::Entropy.new(mode)) do |b|
        with b yield b
      end
    end

    # Define a scoped regex match
    def match(pattern : ::Regex, group : Int32 = 0, name : String? = nil, &)
      sc_name = name || "match_#{pattern.source}"
      scope(sc_name, Selectors::Regex.new(pattern, group)) do |b|
        with b yield b
      end
    end

    # Define a declarative binary protocol frame
    def frame(name : String | Symbol, &)
      fb = FrameBuilder.new(name)
      with fb yield fb
      @engine.register_frame(fb.frame)
      fb.frame
    end

    # Define a context-free generative grammar
    def grammar(name : String | Symbol, max_depth : Int32 = 8, &)
      gb = GrammarBuilder.new(name, max_depth)
      with gb yield gb
      @engine.register_grammar(gb.grammar)
      gb.grammar
    end

    # Extracts diagnostic tokens from error text into the active dictionary
    def harvest(feedback : String) : Array(String)
      @engine.harvest_feedback(feedback)
    end

    # Register post-mutation fixup callback
    def fixup(&block : Buffer -> Nil)
      @engine.add_fixup(&block)
    end

    # Build and return the configured Engine
    def build : Engine
      @engine
    end
  end

  # Primary entry point for constructing a Crowbar pipeline
  def self.define(seed : UInt64? = nil, &) : Engine
    builder = Builder.new(seed)
    with builder yield builder
    builder.build
  end

  # Instant zero-config transform on data (Radamsa-style black box)
  def self.fuzz(input : Buffer | Bytes | String, seed : UInt64? = nil) : String
    engine = seed ? Engine.new(seed) : Engine.new
    engine.transform(input).to_s
  end
end
