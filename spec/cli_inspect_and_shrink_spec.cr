require "./spec_helper"
require "../src/crowbar/cli/app"

describe "Crowbar CLI - Inspect and Shrink commands" do
  before_each do
    FileUtils.rm_rf(".crowbar_test_session")
    ENV["CROWBAR_SESSION_DIR"] = ".crowbar_test_session"
  end

  after_each do
    FileUtils.rm_rf(".crowbar_test_session")
    ENV.delete("CROWBAR_SESSION_DIR")
  end

  it "inspects raw payload and emits terminal report" do
    out_io = IO::Memory.new
    err_io = IO::Memory.new
    in_io = IO::Memory.new("POST /api/v1/auth HTTP/1.1\r\nHost: api.test\r\n\r\n{\"token\":\"xyz\"}")

    app = Crowbar::CLI::App.new(
      in_io: in_io,
      out_io: out_io,
      err_io: err_io,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )

    app.run(["inspect"])
    output = out_io.to_s
    output.should contain("Crowbar Diagnostic Inspector")
    output.should contain("HTTP")
    output.should contain("HTTPHeaders")
    output.should contain("Shannon Entropy")
  end

  it "inspects payload with --json and emits machine-readable metrics" do
    out_io = IO::Memory.new
    err_io = IO::Memory.new
    jwt_sample = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ"
    in_io = IO::Memory.new(jwt_sample)

    app = Crowbar::CLI::App.new(
      in_io: in_io,
      out_io: out_io,
      err_io: err_io,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )

    app.run(["inspect", "--json"])
    json = JSON.parse(out_io.to_s)
    json["format"].as_s.should eq("jwt")
    json["size"].as_i.should eq(jwt_sample.bytesize)
    json["boundaries"].as_a.size.should eq(3)
  end

  it "shrinks a test case using command predicate" do
    # Create temp sample file
    bloated = ("PREFIX_" * 20) + "FATAL_ERROR_TRIGGER" + ("_SUFFIX" * 20)
    temp_in = File.tempfile("bloated_sample", ".txt")
    File.write(temp_in.path, bloated)

    temp_out = File.tempfile("minimized_out", ".txt")

    out_io = IO::Memory.new
    err_io = IO::Memory.new

    app = Crowbar::CLI::App.new(
      in_io: IO::Memory.new,
      out_io: out_io,
      err_io: err_io,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )

    # Use findstr to search for pattern and assert match
    test_cmd = "findstr /C:\"FATAL_ERROR_TRIGGER\" @@"

    begin
      app.run(["shrink", temp_in.path, "--cmd", test_cmd, "--match", "FATAL_ERROR_TRIGGER", "-o", temp_out.path])
      err_str = err_io.to_s
      err_str.should contain("Crowbar Anomaly-Preserving Minimizer")
      err_str.should contain("Reduction complete")

      reduced_data = File.read(temp_out.path)
      reduced_data.should contain("FATAL_ERROR_TRIGGER")
      reduced_data.bytesize.should be < bloated.bytesize
    ensure
      temp_in.delete rescue nil
      temp_out.delete rescue nil
    end
  end

  it "inspects session history and renders mutation heatmap" do
    # Initialize session with baseline
    in_io = IO::Memory.new("ABCDEF0123456789")
    app = Crowbar::CLI::App.new(
      in_io: in_io,
      out_io: IO::Memory.new,
      err_io: IO::Memory.new,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )
    app.run(["session", "heat_test", "next"])

    # Generate another mutant
    app2 = Crowbar::CLI::App.new(
      in_io: IO::Memory.new,
      out_io: IO::Memory.new,
      err_io: IO::Memory.new,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )
    app2.run(["session", "heat_test", "next"])

    # Now inspect the session
    out_inspect = IO::Memory.new
    app3 = Crowbar::CLI::App.new(
      in_io: IO::Memory.new,
      out_io: out_inspect,
      err_io: IO::Memory.new,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )
    app3.run(["session", "heat_test", "inspect"])

    inspect_output = out_inspect.to_s
    inspect_output.should contain("heat_test")
    inspect_output.should contain("Session Mutation Heatmap")
    inspect_output.should contain("Coverage:")
  end

  it "shrinks a session mutant via crowbar session <id> shrink <#>" do
    in_io = IO::Memory.new("TARGET_" * 50)
    app = Crowbar::CLI::App.new(
      in_io: in_io,
      out_io: IO::Memory.new,
      err_io: IO::Memory.new,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )
    app.run(["session", "shrink_sess", "next"])

    out_shrink = IO::Memory.new
    err_shrink = IO::Memory.new
    app2 = Crowbar::CLI::App.new(
      in_io: IO::Memory.new,
      out_io: out_shrink,
      err_io: err_shrink,
      exit_handler: ->(code : Int32) { raise Crowbar::CLI::ExitException.new(code) }
    )
    app2.run(["session", "shrink_sess", "shrink", "1", "--cmd", "findstr /C:\"TARGET_\" @@", "--match", "TARGET_"])

    err_str = err_shrink.to_s
    err_str.should contain("Crowbar Session Mutant Shrinker")
    err_str.should contain("Reduction complete")
    out_shrink.to_s.should contain("TARGET_")
    out_shrink.to_s.bytesize.should be < 350
  end
end
