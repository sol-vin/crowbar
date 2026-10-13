require "./spec_helper"
require "../src/crowbar/minimizer/reducer"

describe Crowbar::Minimizer::Reducer do
  it "reduces a bloated buffer to the minimal triggering substring" do
    # 1000-byte bloated buffer containing "TRIGGER_CRASH"
    bloated = ("A" * 500) + "TRIGGER_CRASH" + ("B" * 500)
    buf = Crowbar::Buffer.new(bloated)

    reducer = Crowbar::Minimizer::Reducer.new(
      predicate: ->(b : Crowbar::Buffer) { b.to_s.includes?("TRIGGER_CRASH") }
    )

    reduced = reducer.reduce(buf)
    reduced.to_s.should eq("TRIGGER_CRASH")
    reduced.size.should eq(13)
  end

  it "strictly preserves duplicate keys and structural anomalies" do
    # JSON with duplicate keys and trailing junk
    json_with_duplicate_keys = %({"role": "user", "padding": "lots of useless junk here 1234567890", "role": "admin"})
    buf = Crowbar::Buffer.new(json_with_duplicate_keys)

    # Predicate requires BOTH duplicate keys to be present (e.g. testing parser differential bug)
    predicate = ->(b : Crowbar::Buffer) {
      str = b.to_s
      str.includes?(%("role": "user")) && str.includes?(%("role": "admin"))
    }

    reducer = Crowbar::Minimizer::Reducer.new(predicate: predicate)
    reduced = reducer.reduce(buf)

    # Both duplicate keys MUST be preserved in the minimized output!
    reduced.to_s.should contain(%("role": "user"))
    reduced.to_s.should contain(%("role": "admin"))
    reduced.to_s.should_not contain("lots of useless junk")
    reduced.size.should be < buf.size
  end

  it "slices irrelevant lines in multi-line payloads" do
    multi_line = "line 1: header info\nline 2: benign data\nline 3: CRITICAL_FAULT\nline 4: footer info\n"
    buf = Crowbar::Buffer.new(multi_line)

    reducer = Crowbar::Minimizer::Reducer.new(
      predicate: ->(b : Crowbar::Buffer) { b.to_s.includes?("CRITICAL_FAULT") }
    )

    reduced = reducer.reduce(buf)
    reduced.to_s.should eq("CRITICAL_FAULT")
  end

  it "raises ArgumentError when initial input does not trigger predicate" do
    buf = Crowbar::Buffer.new("benign input")
    reducer = Crowbar::Minimizer::Reducer.new(
      predicate: ->(b : Crowbar::Buffer) { b.to_s.includes?("CRASH") }
    )

    expect_raises(ArgumentError, "Initial input does not satisfy failure predicate") do
      reducer.reduce(buf)
    end
  end

  it "invokes progress callback as reductions occur" do
    bloated = ("X" * 100) + "FATAL" + ("Y" * 100)
    buf = Crowbar::Buffer.new(bloated)

    progress_events = [] of Tuple(Int32, Int32, Int32)
    cb = ->(iter : Int32, cur : Int32, orig : Int32) {
      progress_events << {iter, cur, orig}
      nil
    }

    reducer = Crowbar::Minimizer::Reducer.new(
      predicate: ->(b : Crowbar::Buffer) { b.to_s.includes?("FATAL") },
      progress_callback: cb
    )

    reduced = reducer.reduce(buf)
    reduced.to_s.should eq("FATAL")
    progress_events.size.should be > 1
    progress_events.last[1].should eq(5)
  end
end
