require "json"
require "digest/sha256"
require "../buffer"

module Crowbar::Campaign
  # Status of a single mutation fuzzing iteration
  enum ExecutionStatus
    Pass
    ExpectedError
    Crash
    Timeout
    Anomaly

    def to_s(io : IO) : Nil
      case self
      when Pass          then io << "PASS"
      when ExpectedError then io << "EXPECTED_ERROR"
      when Crash         then io << "CRASH"
      when Timeout       then io << "TIMEOUT"
      when Anomaly       then io << "ANOMALY"
      end
    end
  end

  # Result of executing a mutated test case
  struct IterationResult
    property target_name : String
    property iteration : Int32
    property status : ExecutionStatus
    property duration : Time::Span
    property input_size : Int32
    property mutant_size : Int32
    property entropy : Float64
    property mutations_applied : Array(String)
    property error_class : String?
    property error_message : String?
    property backtrace : Array(String)?
    property mutant : Buffer?

    def initialize(
      @target_name : String,
      @iteration : Int32,
      @status : ExecutionStatus,
      @duration : Time::Span,
      @input_size : Int32,
      @mutant_size : Int32,
      @entropy : Float64,
      @mutations_applied : Array(String) = [] of String,
      @error_class : String? = nil,
      @error_message : String? = nil,
      @backtrace : Array(String)? = nil,
      @mutant : Buffer? = nil,
    )
    end
  end

  # Recorded failure or unhandled exception with reproducer artifacts
  class CrashRecord
    include JSON::Serializable

    getter id : String
    getter target_name : String
    getter iteration : Int32
    getter error_class : String
    getter error_message : String
    getter backtrace : Array(String)
    getter reproducer_base64 : String
    getter reproducer_size : Int32
    getter reproducer_entropy : Float64
    property minimized_base64 : String?
    property minimized_size : Int32?

    @[JSON::Field(ignore: true)]
    getter reproducer : Buffer

    @[JSON::Field(ignore: true)]
    property minimized_reproducer : Buffer?

    def initialize(
      @target_name : String,
      @iteration : Int32,
      @error_class : String,
      @error_message : String,
      @backtrace : Array(String),
      @reproducer : Buffer,
      @reproducer_entropy : Float64,
      @minimized_reproducer : Buffer? = nil,
    )
      @reproducer_size = @reproducer.size
      @reproducer_base64 = Base64.strict_encode(@reproducer.to_slice)

      if min = @minimized_reproducer
        @minimized_size = min.size
        @minimized_base64 = Base64.strict_encode(min.to_slice)
      end

      # Unique crash fingerprint hash
      fingerprint_src = "#{@target_name}:#{@error_class}:#{@error_message.lines.first? || ""}"
      @id = Digest::SHA256.hexdigest(fingerprint_src)[0, 12]
    end
  end
end
