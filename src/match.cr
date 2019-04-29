class Crowbar::Match
  property start = 0
  property finish = 0
  property string = ""
  property? matched = false

  def range
    (start..finish)
  end
end