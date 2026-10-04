module Crowbar::Evolution
  # Multi-Armed Bandit credit assignment using the Upper Confidence Bound (UCB1) algorithm.
  # Dynamically balances exploitation of high-yield mutators/scopes with exploration of less-tested ones.
  class Bandit
    class Arm
      property name : String
      property pulls : Int64 = 0_i64
      property rewards : Float64 = 0.0

      def initialize(@name : String)
      end

      def average_reward : Float64
        pulls > 0 ? (rewards / pulls) : 0.0
      end

      # Computes Upper Confidence Bound 1
      def ucb_score(total_pulls : Int64, exploration_coeff : Float64 = 1.41421356) : Float64
        return Float64::INFINITY if pulls == 0_i64
        return average_reward if total_pulls <= 0_i64

        exploration_term = exploration_coeff * Math.sqrt(Math.log(total_pulls) / pulls)
        average_reward + exploration_term
      end
    end

    getter arms : Hash(String, Arm)
    property total_pulls : Int64 = 0_i64
    property exploration_coeff : Float64 = 1.41421356

    def initialize(@exploration_coeff : Float64 = 1.41421356)
      @arms = Hash(String, Arm).new
    end

    # Ensure an arm is registered
    def ensure_arm(name : String) : Arm
      @arms[name] ||= Arm.new(name)
    end

    # Record that an arm was executed
    def record_pull(name : String)
      arm = ensure_arm(name)
      arm.pulls += 1
      @total_pulls += 1
    end

    # Credit an arm with a reward
    def reward(name : String, value : Float64)
      arm = ensure_arm(name)
      arm.rewards += value
    end

    # Select the best arm among available names based on UCB1 score
    def select(available_arms : Array(String), prng : PRNG) : String
      raise ArgumentError.new("available_arms cannot be empty") if available_arms.empty?

      # If any arms have never been pulled, randomly pick among the unpulled arms
      unpulled = available_arms.select { |name| (arm = @arms[name]?) ? arm.pulls == 0 : true }
      return prng.choice(unpulled) unless unpulled.empty?

      # Otherwise select arm with maximum UCB1 score
      best_arm = available_arms.first
      best_score = -Float64::INFINITY

      available_arms.each do |name|
        arm = ensure_arm(name)
        score = arm.ucb_score(@total_pulls, @exploration_coeff)
        if score > best_score
          best_score = score
          best_arm = name
        end
      end

      best_arm
    end

    # Retrieve score for inspection/telemetry
    def score_for(name : String) : Float64
      if arm = @arms[name]?
        arm.ucb_score(@total_pulls, @exploration_coeff)
      else
        Float64::INFINITY
      end
    end

    def pulls_for(name : String) : Int64
      @arms[name]?.try(&.pulls) || 0_i64
    end

    def rewards_for(name : String) : Float64
      @arms[name]?.try(&.rewards) || 0.0
    end
  end
end
