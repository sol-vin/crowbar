require "json"
require "./transformation_step"

module Crowbar
  # Serializable record representing a single generated mutant in a session lifecycle.
  # Retains full provenance, seed coordinates, diff metrics, and reward state.
  class SessionItem
    include JSON::Serializable

    property iteration : Int32
    property timestamp : Time
    property size : Int32
    property diff_count : Int32
    property mutators : Array(String)
    property steps : Array(TransformationStep)
    property seed : UInt64
    property seek_offset : Int64
    property reward : Float64?
    property file_path : String?

    def initialize(
      @iteration : Int32,
      @size : Int32,
      @diff_count : Int32,
      @mutators : Array(String),
      @steps : Array(TransformationStep),
      @seed : UInt64,
      @seek_offset : Int64,
      @reward : Float64? = nil,
      @file_path : String? = nil,
      @timestamp : Time = Time.utc,
    )
    end

    def rewarded? : Bool
      !@reward.nil?
    end

    def positive_reward? : Bool
      if r = @reward
        r > 0.0
      else
        false
      end
    end
  end
end
