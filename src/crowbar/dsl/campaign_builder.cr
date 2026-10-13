require "../campaign/target"
require "../campaign/runner"
require "../campaign/battery"
require "../rules/registry"

module Crowbar::DSL
  # Declarative builder for configuring an individual Campaign fuzz target
  class TargetBuilder
    getter target : Campaign::Target

    def initialize(name : String, category : Campaign::TargetCategory = Campaign::TargetCategory::Custom)
      @target = Campaign::Target.new(name: name, category: category)
    end

    def category(cat : Campaign::TargetCategory)
      @target.category = cat
    end

    def category(cat : Symbol)
      case cat
      when :serialization then @target.category = Campaign::TargetCategory::Serialization
      when :security      then @target.category = Campaign::TargetCategory::Security
      when :networking    then @target.category = Campaign::TargetCategory::Networking
      when :grammar       then @target.category = Campaign::TargetCategory::Grammar
      when :archive       then @target.category = Campaign::TargetCategory::Archive
      when :protocol      then @target.category = Campaign::TargetCategory::Protocol
      else                     @target.category = Campaign::TargetCategory::Custom
      end
    end

    def sample(data : Buffer | Bytes | String)
      @target.add_sample(data)
    end

    def samples(*items : Buffer | Bytes | String)
      items.each { |item| sample(item) }
    end

    def rule(format : Symbol)
      rule_instance = case format
                      when :json                 then Rules::JSONRule.new
                      when :yaml, :yml           then Rules::YAMLRule.new
                      when :jwt                  then Rules::JWTRule.new
                      when :http                 then Rules::HTTPRule.new
                      when :csv, :tsv            then Rules::CSVRule.new
                      when :url, :uri            then Rules::URLRule.new
                      when :base64, :b64         then Rules::Base64Rule.new
                      when :packet, :ipv4, :pcap then Rules::PacketRule.new
                      when :markdown, :md        then Rules::MarkdownRule.new
                      when :tar, :ustar          then Rules::TarRule.new
                      when :zip, :pkzip          then Rules::ZipRule.new
                      when :seven_zip, :"7z"     then Rules::SevenZipRule.new
                      else
                        nil
                      end
      @target.add_rule(rule_instance) if rule_instance
      rule_instance
    end

    def rule(instance : Rule)
      @target.add_rule(instance)
    end

    def expected_error(err_class : Exception.class)
      @target.add_expected_error(err_class)
    end

    def expected_errors(*classes : Exception.class)
      classes.each { |c| expected_error(c) }
    end

    def timeout(span : Time::Span)
      @target.timeout = span
    end

    def timeout(ms : Int32)
      @target.timeout = ms.milliseconds
    end

    def execute(&block : Buffer -> Nil)
      @target.execution = block
    end
  end

  # Declarative builder for configuring an entire mutation fuzzing campaign
  class CampaignBuilder
    getter runner : Campaign::Runner

    def initialize(name : String = "Nightly Mutation Fuzzing")
      @runner = Campaign::Runner.new(name: name)
    end

    def name(val : String)
      @runner.name = val
    end

    def iterations(count : Int32)
      @runner.iterations_per_target = count
    end

    def iterations_per_target(count : Int32)
      @runner.iterations_per_target = count
    end

    def duration(span : Time::Span)
      @runner.max_duration = span
    end

    def duration(sec : Int32)
      @runner.max_duration = sec.seconds
    end

    def seed(val : UInt64)
      @runner.seed = val
    end

    def auto_shrink(val : Bool)
      @runner.auto_shrink = val
    end

    def watchdog(span : Time::Span)
      @runner.watchdog_interval = span
    end

    def watchdog(sec : Int32)
      @runner.watchdog_interval = sec.seconds
    end

    # Define a custom fuzzing target
    def target(name : String, category : Campaign::TargetCategory = Campaign::TargetCategory::Custom, &)
      builder = TargetBuilder.new(name, category)
      with builder yield builder
      @runner.add_target(builder.target)
      builder.target
    end

    # Adds an existing preconfigured target
    def add_target(target : Campaign::Target)
      @runner.add_target(target)
    end

    # Imports all standard battery targets (JSON, YAML, JWT, HTTP, CSV, URI, Base64, Packet)
    def include_default_targets!
      Campaign::Battery.all_targets.each do |target|
        @runner.add_target(target)
      end
    end

    # Imports a specific target from the standard battery
    def include_target(name : String)
      target = case name.downcase
               when "json", "json_parser"   then Campaign::Battery.json_target
               when "yaml", "yaml_parser"   then Campaign::Battery.yaml_target
               when "jwt", "jwt_validator"  then Campaign::Battery.jwt_target
               when "http", "http_request"  then Campaign::Battery.http_target
               when "csv", "csv_parser"     then Campaign::Battery.csv_target
               when "uri", "uri_parser"     then Campaign::Battery.uri_target
               when "base64", "base64_decoder" then Campaign::Battery.base64_target
               when "packet", "packet_framing" then Campaign::Battery.packet_target
               else
                 nil
               end
      if target
        @runner.add_target(target)
      else
        raise ArgumentError.new("Unknown battery target '#{name}'")
      end
    end

    def on_progress(&block : String, Int32, Int32, Campaign::IterationResult -> Nil)
      @runner.on_progress = block
    end

    def on_heartbeat(&block : Int32, Float64 -> Nil)
      @runner.on_heartbeat = block
    end

    def on_crash(&block : Campaign::CrashRecord -> Nil)
      @runner.on_crash = block
    end

    def build : Campaign::Runner
      @runner
    end

    def run : Campaign::CampaignReport
      @runner.run
    end
  end
end

module Crowbar
  # Top-level declarative DSL entry point for configuring and running a Campaign
  def self.campaign(name : String = "Nightly Mutation Fuzzing", &) : Campaign::CampaignReport
    builder = DSL::CampaignBuilder.new(name)
    with builder yield builder
    builder.run
  end

  # Constructs a configured Campaign runner without immediately executing it
  def self.define_campaign(name : String = "Nightly Mutation Fuzzing", &) : Campaign::Runner
    builder = DSL::CampaignBuilder.new(name)
    with builder yield builder
    builder.build
  end
end
