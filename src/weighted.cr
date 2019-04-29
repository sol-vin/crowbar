module Weighted
  property weight : Float32 = 0.5_f32
  property personal_weight : Float32 = 1.0_f32

  MAX_GAIN = 0.05
  MAX_LOSS = 0.1

  def total_weight
    @weight * @personal_weight
  end

  def lose
    @weight -= MAX_LOSS
  end

  def gain
    @weight += (MAX_GAIN * @personal_weight)
  end
end