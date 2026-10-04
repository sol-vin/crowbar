require "./spec_helper"
require "file_utils"

describe "Crowbar Session Radamsa Features Integration" do
  test_dir = File.join(Dir.tempdir, "crowbar_test_session_radamsa_#{Random.rand(10000)}")

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

  it "renders output templates via 'crowbar session <id> next -t ...'" do
    sess_id = "test_tmpl_sess"
    in_io = IO::Memory.new("SAMPLE_PAYLOAD\n")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    app = Crowbar::CLI::App.new(in_io: in_io, out_io: out_io, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app.run(["session", sess_id, "next", "-t", "<html>%f</html>"])

    out_str = out_io.to_s
    out_str.should start_with("<html>")
    out_str.should end_with("</html>")

    # Session object should now exist
    session = Crowbar::Session.load(sess_id).not_nil!
    session.iteration.should eq(1)
  end

  it "persists template configured via 'crowbar session <id> setup --template ...'" do
    sess_id = "test_setup_tmpl"
    in_io = IO::Memory.new("INITIAL_DATA\n")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    app = Crowbar::CLI::App.new(in_io: in_io, out_io: out_io, err_io: err_io, exit_handler: ->(_c : Int32) { })
    # 1. Initialize session
    app.run(["session", sess_id, "next"])

    # 2. Setup template
    out_setup = IO::Memory.new
    app_setup = Crowbar::CLI::App.new(in_io: IO::Memory.new, out_io: out_setup, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app_setup.run(["session", sess_id, "setup", "--template", "PREFIX[%f]SUFFIX"])

    # Verify session template is persisted
    session = Crowbar::Session.load(sess_id).not_nil!
    session.template.should eq("PREFIX[%f]SUFFIX")

    # 3. Next mutant automatically uses persisted template
    out_next = IO::Memory.new
    app_next = Crowbar::CLI::App.new(in_io: IO::Memory.new, out_io: out_next, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app_next.run(["session", sess_id, "next"])

    out_str = out_next.to_s
    out_str.should start_with("PREFIX[")
    out_str.should end_with("]SUFFIX")
  end

  it "guarantees non-duplicate outputs across sessions with --unique" do
    sess_id = "test_unique_sess"
    in_io = IO::Memory.new("hello fuzzing world\n")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    app = Crowbar::CLI::App.new(in_io: in_io, out_io: out_io, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app.run(["session", sess_id, "next", "--unique"])

    # Generate 5 consecutive mutants with --unique
    emitted = Set(String).new
    emitted.add(out_io.to_s)

    5.times do
      out_iter = IO::Memory.new
      app_iter = Crowbar::CLI::App.new(in_io: IO::Memory.new, out_io: out_iter, err_io: err_io, exit_handler: ->(_c : Int32) { })
      app_iter.run(["session", sess_id, "next", "--unique"])
      mutant = out_iter.to_s
      emitted.should_not contain(mutant)
      emitted.add(mutant)
    end

    session = Crowbar::Session.load(sess_id).not_nil!
    session.unique_enabled.should be_true
    session.seen_hashes.size.should be >= 6
  end

  it "configures and uses new mutators sec and fuse in sessions" do
    sess_id = "test_sec_fuse_sess"
    in_io = IO::Memory.new("param1=value1&param2=value2\n")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    app = Crowbar::CLI::App.new(in_io: in_io, out_io: out_io, err_io: err_io, exit_handler: ->(_c : Int32) { })
    # 1. Initialize session
    app.run(["session", sess_id, "next"])

    # 2. Setup with sec and fuse mutators
    out_setup = IO::Memory.new
    app_setup = Crowbar::CLI::App.new(in_io: IO::Memory.new, out_io: out_setup, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app_setup.run(["session", sess_id, "setup", "--set-mutators", "sec,fuse"])

    session = Crowbar::Session.load(sess_id).not_nil!
    session.selected_mutations.should eq("sec,fuse")

    # 3. Next mutant uses sec or fuse
    out_next = IO::Memory.new
    app_next = Crowbar::CLI::App.new(in_io: IO::Memory.new, out_io: out_next, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app_next.run(["session", sess_id, "next"])

    session_after = Crowbar::Session.load(sess_id).not_nil!
    session_after.last_mutators.should_not be_empty
    ["sec", "splice"].should contain(session_after.last_mutators.first)
  end

  it "advances PRNG state via seek offset in session" do
    sess_id = "test_seek_sess"
    in_io = IO::Memory.new("1234567890abcdef\n")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    app = Crowbar::CLI::App.new(in_io: in_io, out_io: out_io, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app.run(["session", sess_id, "next", "-S", "50"])

    session = Crowbar::Session.load(sess_id).not_nil!
    session.seek_offset.should eq(50)
  end

  it "displays template and unique filter in session status" do
    sess_id = "test_status_sess"
    in_io = IO::Memory.new("baseline test\n")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    app = Crowbar::CLI::App.new(in_io: in_io, out_io: out_io, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app.run(["session", sess_id, "next", "-t", "OUT:%f", "-u"])

    status_io = IO::Memory.new
    app_status = Crowbar::CLI::App.new(in_io: IO::Memory.new, out_io: status_io, err_io: err_io, exit_handler: ->(_c : Int32) { })
    app_status.run(["session", sess_id, "status"])

    status_str = status_io.to_s
    status_str.should contain("Template:")
    status_str.should contain("OUT:%f")
    status_str.should contain("Unique Filter:")
    status_str.should contain("enabled")
  end
end
