module Weighted
  property current_weight : Float32 = 0.5_f32
  property weight : Float32 = 1.0_f32

  MAX_GAIN = 0.05
  MAX_LOSS = 0.1

  def total_weight
    @weight * @current_weight
  end

  def lose
    @current_weight -= MAX_LOSS
  end

  def gain
    @current_weight += (MAX_GAIN * @weight)
  end
end