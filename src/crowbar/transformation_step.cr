require "json"

module Crowbar
  # Categories of transformative actions in the mutation pipeline
  enum StepCategory
    Parent
    Selector
    Mutator
    Rule
    Fixup
    Template
    Uniqueness

    def to_badge : String
      case self
      when Parent     then "[PARENT]"
      when Selector   then "[SCOPE]"
      when Mutator    then "[MUTATOR]"
      when Rule       then "[RULE]"
      when Fixup      then "[FIXUP]"
      when Template   then "[TEMPLATE]"
      when Uniqueness then "[UNIQUE]"
      else                 "[STEP]"
      end
    end
  end

  # Represents an individual transformative operation executed on a buffer.
  # Provides granular provenance, coordinate bounding, and human-readable descriptions.
  struct TransformationStep
    include JSON::Serializable

    property index : Int32
    property category : StepCategory
    property name : String
    property description : String
    property range_start : Int32?
    property range_end : Int32?
    property diff_bytes : Int32 = 0
    property details : Hash(String, String) = Hash(String, String).new

    def initialize(
      @index : Int32,
      @category : StepCategory,
      @name : String,
      @description : String,
      @range_start : Int32? = nil,
      @range_end : Int32? = nil,
      @diff_bytes : Int32 = 0,
      @details : Hash(String, String) = Hash(String, String).new,
    )
    end

    def range_string : String
      if (s = @range_start) && (e = @range_end)
        "[#{s}...#{e}]"
      else
        "global"
      end
    end

    def diff_string : String
      if @diff_bytes > 0
        "+#{@diff_bytes} B"
      elsif @diff_bytes < 0
        "#{@diff_bytes} B"
      else
        "0 B"
      end
    end
  end
end
