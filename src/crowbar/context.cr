require "./prng"
require "./metadata"

module Crowbar
  # Execution context passed to mutators, selectors, and rules.
  # Manages the deterministic PRNG, iteration counter, and current metadata trail.
  class Context
    getter prng : PRNG
    property iteration : Int64 = 0_i64
    property current_metadata : Metadata?
    property secondary_samples : Array(Buffer) = [] of Buffer

    def initialize(seed : UInt64 = PRNG.default_seed)
      @prng = PRNG.new(seed)
    end

    def add_sample(buf : Buffer) : Nil
      @secondary_samples << buf
    end

    def seek(offset : Int) : Nil
      @prng.seek(offset)
    end

    def seed : UInt64
      @prng.seed
    end

    def seed=(new_seed : UInt64)
      @prng.seed = new_seed
    end

    def begin_iteration(input_size : Int32) : Metadata
      @iteration += 1
      meta = Metadata.new(
        seed: @prng.seed,
        iteration: @iteration,
        input_size: input_size
      )
      @current_metadata = meta
      meta
    end

    def record_mutation(name : String, range : Tuple(Int32, Int32)? = nil, description : String? = nil)
      if meta = @current_metadata
        meta.record_mutation(name, range, description)
      end
    end

    def record_step(
      category : StepCategory,
      name : String,
      description : String,
      range : Tuple(Int32, Int32)? = nil,
      diff_bytes : Int32 = 0,
      details : Hash(String, String) = Hash(String, String).new,
    ) : TransformationStep?
      if meta = @current_metadata
        meta.record_step(category, name, description, range, diff_bytes, details)
      else
        nil
      end
    end
  end
end
