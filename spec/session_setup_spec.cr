require "./spec_helper"
require "file_utils"

describe "Session Setup & Scope Configuration" do
  test_dir = ".crowbar/test_setup_sessions"

  before_each do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
  end

  after_each do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
  end

  it "manages active rules dynamically" do
    base = Crowbar::Buffer.new("Sample baseline data")
    sess = Crowbar::Session.new("test_rules", base)

    sess.active_rules.should be_empty
    sess.add_rule("http")
    sess.active_rules.should eq(["http"])
    sess.rule_name.should eq("http")

    sess.add_rule("json")
    sess.active_rules.should eq(["http", "json"])

    sess.remove_rule("http")
    sess.active_rules.should eq(["json"])

    sess.clear_rules
    sess.active_rules.should be_empty
    sess.rule_name.should be_nil
  end

  it "auto-detects rule from media baseline on initialization or setup" do
    # PNG baseline
    png_bytes = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]
    png_buf = Crowbar::Buffer.new(png_bytes)
    sess = Crowbar::Session.load_or_create("png_sess", png_buf, dir: test_dir)

    sess.active_rules.should eq(["png"])
    sess.rule_name.should eq("png")

    # MP3 baseline
    mp3_bytes = Bytes[0xFF, 0xFB, 0x90, 0x64, 0x11, 0x22, 0x33, 0x44]
    mp3_buf = Crowbar::Buffer.new(mp3_bytes)
    sess_mp3 = Crowbar::Session.load_or_create("mp3_sess", mp3_buf, dir: test_dir)

    sess_mp3.active_rules.should eq(["mp3"])
    sess_mp3.rule_name.should eq("mp3")
  end

  it "manages mutator pool and patterns" do
    base = Crowbar::Buffer.new("Test baseline")
    sess = Crowbar::Session.new("test_mutators", base)

    sess.set_mutators(["num", "bf", "wd"])
    sess.selected_mutations.should eq("num,bf,wd")

    sess.add_mutator("sr")
    sess.selected_mutations.should eq("num,bf,wd,sr")

    sess.remove_mutator("bf")
    sess.selected_mutations.should eq("num,wd,sr")

    sess.set_pattern("burst")
    sess.pattern_name.should eq("burst")

    sess.reset_mutators
    sess.selected_mutations.should be_nil
  end

  it "configures scoped target regions and rehydrates them into Engine" do
    base = Crowbar::Buffer.new("HEADER123456BODY7890FOOTER")
    sess = Crowbar::Session.new("test_scopes", base)

    # Add header scope
    sess.add_scope("head", "header", {"length" => "6"}, weight: 2.0)
    # Add delimited field scope
    sess.add_scope("field", "delimited", {"index" => "1", "delimiter" => ","}, weight: 1.5)
    # Add byte range scope
    sess.add_scope("range", "range", {"start" => "10", "end" => "20"}, weight: 1.0)

    sess.scopes.size.should eq(3)
    sess.save(test_dir)

    # Load from disk and verify serialization
    loaded = Crowbar::Session.load("test_scopes", test_dir).not_nil!
    loaded.scopes.size.should eq(3)
    loaded.scopes[0].name.should eq("head")
    loaded.scopes[0].selector_type.should eq("header")
    loaded.scopes[0].params["length"].should eq("6")
    loaded.scopes[0].weight.should eq(2.0)

    # Re-hydrate Engine
    engine = loaded.build_engine
    engine.scopes.size.should eq(3)
    engine.scopes.map(&.name).should eq(["head", "field", "range"])

    # Test removing scope
    loaded.remove_scope("field")
    loaded.scopes.size.should eq(2)
    loaded.scopes.map(&.name).should eq(["head", "range"])
  end

  it "generates mutants adhering to configured setup and records history" do
    png_bytes = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    buf = Crowbar::Buffer.new(png_bytes)
    sess = Crowbar::Session.load_or_create("exec_test", buf, dir: test_dir)
    sess.add_scope("tail", "footer", {"length" => "4"})
    sess.set_mutators(["bf", "num"])

    mutant = sess.next_mutant(test_dir)
    mutant.should_not be_nil
    sess.iteration.should eq(1)

    sess.reward(0.8, test_dir)
    sess.last_reward.should eq(0.8)
    sess.history.size.should eq(2) # 1 next + 1 reward
  end
end
