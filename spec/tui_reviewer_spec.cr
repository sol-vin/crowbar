require "./spec_helper"
require "../src/crowbar"
require "file_utils"
require "json"

describe "Crowbar TUI Reviewer & SummaryView" do
  test_dir = File.join(Dir.tempdir, "crowbar_tui_spec_#{Random.rand(10000)}")

  before_each do
    FileUtils.mkdir_p(test_dir)
    ENV["CROWBAR_SESSION_DIR"] = test_dir
  end

  after_each do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
    ENV.delete("CROWBAR_SESSION_DIR")
  end

  after_all do
    FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
    ENV.delete("CROWBAR_SESSION_DIR")
  end

  describe "SummaryView (Non-TTY / Headless Mode)" do
    it "renders human-readable ASCII/ANSI summary table" do
      sess = Crowbar::Session.new("tui_summary_sess", Crowbar::Buffer.new("Test baseline"))
      sess.save(test_dir)
      sess.next_mutant(dir: test_dir)
      sess.next_mutant(dir: test_dir)

      io = IO::Memory.new
      Crowbar::TUI::SummaryView.render(sess, io, limit: 10, json: false)
      output = io.to_s

      output.should contain("Crowbar Session Reviewer: tui_summary_sess")
      output.should contain("Baseline: 13 B")
      output.should contain("Items Tracked: 2")
      output.should contain("Mutators")
    end

    it "renders machine-readable JSON structure" do
      sess = Crowbar::Session.new("tui_json_sess", Crowbar::Buffer.new("Test JSON baseline"))
      sess.save(test_dir)
      sess.next_mutant(dir: test_dir)

      io = IO::Memory.new
      Crowbar::TUI::SummaryView.render(sess, io, limit: 10, json: true)
      output = io.to_s

      parsed = JSON.parse(output)
      parsed["session_id"].as_s.should eq("tui_json_sess")
      parsed["items"].as_a.size.should eq(1)
      parsed["items"][0]["iteration"].as_i.should eq(1)
      parsed["items"][0]["steps"].as_a.size.should be > 0
    end
  end

  describe "ReviewerModel (TEA State Transitions)" do
    it "navigates iterations, cycles tabs, and applies rewards via key events" do
      sess = Crowbar::Session.new("tea_model_sess", Crowbar::Buffer.new("Interactive TUI baseline"))
      sess.save(test_dir)
      sess.next_mutant(dir: test_dir)
      sess.next_mutant(dir: test_dir)
      sess.next_mutant(dir: test_dir)

      model = Crowbar::TUI::ReviewerModel.new(sess, session_dir: test_dir, width: 90, height: 25)
      model.selected_index.should eq(0)
      model.active_tab.should eq(0)

      # 1. Navigation keys
      model.update(Opal::TEA::KeyMsg.new("down"))
      model.selected_index.should eq(1)

      model.update(Opal::TEA::KeyMsg.new("j"))
      model.selected_index.should eq(2)

      model.update(Opal::TEA::KeyMsg.new("up"))
      model.selected_index.should eq(1)

      # 2. Tab switching
      model.update(Opal::TEA::KeyMsg.new("2"))
      model.active_tab.should eq(1)

      model.update(Opal::TEA::KeyMsg.new("tab"))
      model.active_tab.should eq(2)

      model.update(Opal::TEA::KeyMsg.new("1"))
      model.active_tab.should eq(0)

      # 3. Quick penalty (-)
      model.update(Opal::TEA::KeyMsg.new("-"))
      sess.get_item(2).not_nil!.reward.should eq(-1.0)
      model.status_message.not_nil!.should contain("Penalized item #2")

      # 4. Interactive reward input (+) -> Enter
      model.update(Opal::TEA::KeyMsg.new("+"))
      model.reward_mode.should be_true

      model.update(Opal::TEA::KeyMsg.new("enter"))
      model.reward_mode.should be_false
      sess.get_item(2).not_nil!.reward.should eq(1.0)
      model.status_message.not_nil!.should contain("Rewarded item #2 with +1.0")

      # 5. Export key (e)
      model.update(Opal::TEA::KeyMsg.new("e"))
      export_file = "mutant_tea_model_sess_iter_2.bin"
      File.exists?(export_file).should be_true
      File.delete(export_file)

      # 6. View rendering
      view_output = model.view
      view_output.size.should be > 0
      view_output.should contain("Crowbar Session Reviewer")
      view_output.should contain("tea_model_sess")
    end

    it "runs headless event loop cleanly with Opal MockDriver" do
      sess = Crowbar::Session.new("mock_driver_sess", Crowbar::Buffer.new("Mock driver payload"))
      sess.save(test_dir)
      sess.next_mutant(dir: test_dir)

      model = Crowbar::TUI::ReviewerModel.new(sess, session_dir: test_dir, width: 80, height: 24)
      mock_driver = Opal::Terminal::MockDriver.new(width: 80, height: 24)

      # Enqueue events: move down, switch tab, quit
      mock_driver.event_queue << Opal::Terminal::KeyEvent.new("j")
      mock_driver.event_queue << Opal::Terminal::KeyEvent.new("2")
      mock_driver.event_queue << Opal::Terminal::KeyEvent.new("q")

      program = Opal::TEA::Program.new(
        model: model,
        driver: mock_driver,
        alt_screen: false,
        mouse_enabled: false
      )

      final_model = program.run.as(Crowbar::TUI::ReviewerModel)
      final_model.should_not be_nil
      final_model.active_tab.should eq(1)
    end
  end
end
