class Crowbar::Selector::Regex < Crowbar::Selector
  @regex = //
  @pos = 0
  def initialize(crowbar, @regex)
    super crowbar do |cr|
      yield cr
    end
  end

  def matches : Array(Crowbar::Match)
    # Get a list of all regex matches
    regex_matches = crowbar.working_input.scan(@regex)

    # Translate them to custom match format
    matches = regex_matches.map do |m|
      match = Crowbar::Match.new
      match.start = m.begin.as(Int32)
      match.finish = m.end.as(Int32)
      match.string = m[0]
      match.matched = true
      match
    end

    # Will include non-matches
    full_matches = [] of Crowbar::Match

    # Go through each match, and add it to the list of full_matches,
    # as well as adding the non-matched input with it
    matches.each_with_index do |match, m_index|
      # If we are the first match, and we start at the beginning of the string
      if match.start == 0 && m_index == 0
        # Add it to the matches
        full_matches << match
      # If we are the only m_index, and also there is text behind it and in front of it
      elsif m_index == 0 && matches.size == 1 && match.finish < crowbar.working_input.size-1
        # make a new match
        m1 = Crowbar::Match.new
        m1.finish = match.start-1
        m1.string = crowbar.working_input[m1.range]
        m1.matched = false

        m2 = Crowbar::Match.new
        m2.start = match.finish
        m2.finish = crowbar.working_input.size
        m2.string = crowbar.working_input[m2.range]
        m2.matched = false

        full_matches << m1
        full_matches << match
        full_matches << m2
      # if we are the first m_index, but there is text in front
      elsif m_index == 0
        # make a new match
        m = Crowbar::Match.new
        m.finish = match.start-1
        m.string = crowbar.working_input[m.range]

        m.matched = false
        full_matches << m
        full_matches << match
      # If we are the last match, and we are at the end of the string
      elsif match.finish == crowbar.working_input.size-1
        # Add it to the matches
        full_matches << match
      # If we are the last index but there is still text after the match
      elsif m_index == (matches.size-1)
        m1 = Crowbar::Match.new
        m1.start = match.finish
        m1.finish = crowbar.working_input.size
        m1.string = crowbar.working_input[m1.range]
        m1.matched = false

        m2 = Crowbar::Match.new
        m2.start = matches[m_index-1].finish
        m2.finish = match.start-1
        m2.string = crowbar.working_input[m2.range]
        m2.matched = false

        full_matches << m2
        full_matches << match
        full_matches << m1
      else
        # Read the match behind it to know where to start getting text from
        m = Crowbar::Match.new
        m.start = matches[m_index-1].finish
        m.finish = match.start-1
        m.string = crowbar.working_input[m.range]
        m.matched = false
        full_matches << m
        full_matches << match
      end
    end
    full_matches
  end 
end