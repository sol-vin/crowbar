require "./base"
require "../mutators/values"

module Crowbar::Rules
  # Structure-preserving rule for RFC 959 FTP command and response streams.
  # Maintains strict CRLF line framing while mutating command arguments (e.g. PORT
  # octets, RETR paths, credentials) or response status codes and messages.
  class FTPRule < Rule
    COMMON_COMMANDS = [
      "USER", "PASS", "ACCT", "CWD", "CDUP", "SMNT", "QUIT", "REIN",
      "PORT", "PASV", "TYPE", "STRU", "MODE", "RETR", "STOR", "STOU",
      "APPE", "ALLO", "REST", "RNFR", "RNTO", "ABOR", "DELE", "RMD",
      "MKD", "PWD", "LIST", "NLST", "SITE", "SYST", "STAT", "HELP", "NOOP",
      "FEAT", "SIZE", "EPSV", "EPRT", "AUTH", "PBSZ", "PROT",
    ]

    RESPONSE_CODES = [
      "125", "150", "200", "211", "215", "220", "221", "226", "227", "230",
      "331", "332", "350", "421", "425", "426", "450", "451", "500", "501",
      "502", "503", "504", "530", "550", "552", "553", "999", "000",
    ]

    property? mutate_responses : Bool = true
    property? mutate_verbs : Bool = false

    def initialize(@weight : Float64 = 1.0, @mutate_responses : Bool = true, @mutate_verbs : Bool = false)
      super(@weight)
    end

    def name : String
      "ftp"
    end

    def description : String
      "Structure-preserving RFC 959 FTP command & response mutation (valid CRLF framing)"
    end

    def match?(buffer : Buffer) : Bool
      str = buffer.to_raw_s
      first_line = str.split("\n", 2)[0].strip("\r")
      return false if first_line.empty?

      # Match 3-digit FTP response (e.g. "220 Service ready")
      return true if first_line =~ /^[1-5]\d\d[\s-]/

      # Match standard FTP command verb
      verb = first_line.split(" ", 2)[0].upcase
      COMMON_COMMANDS.includes?(verb)
    rescue
      false
    end

    def apply(context : Context, buffer : Buffer) : Bool
      raw_str = buffer.to_raw_s
      lines = raw_str.split("\n").map(&.strip("\r"))
      return false if lines.empty?

      mutated_lines = lines.map do |line|
        next line if line.empty?
        mutate_line(line, context)
      end

      # Reconstruct with strict RFC 959 CRLF line termination
      io = IO::Memory.new
      mutated_lines.each do |l|
        io << l << "\r\n"
      end

      reconstructed = io.to_slice
      buffer.replace_range(0, buffer.size, reconstructed)
      context.record_mutation(name)
      true
    rescue
      false
    end

    private def mutate_line(line : String, context : Context) : String
      # Check if this is a response line (e.g. "220 Welcome to FTP")
      if line =~ /^(\d{3})([\s-])(.*)$/
        code = $1
        sep = $2
        msg = $3
        if @mutate_responses && context.prng.rand_bool(0.5)
          case context.prng.rand(3)
          when 0
            code = context.prng.choice(RESPONSE_CODES)
          when 1
            msg = msg + " " + context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
          else
            msg = msg * context.prng.rand(2..4)
          end
        end
        return "#{code}#{sep}#{msg}"
      end

      # Command line: <VERB> [SP <ARGS>]
      parts = line.split(" ", 2)
      verb = parts[0]
      args = parts.size > 1 ? parts[1] : ""

      if @mutate_verbs && context.prng.rand_bool(0.2)
        verb = context.prng.choice(COMMON_COMMANDS)
      end

      mutated_args = case verb.upcase
                     when "PORT"
                       mutate_port_args(args, context)
                     when "RETR", "STOR", "APPE", "CWD", "DELE", "RMD", "MKD"
                       mutate_path_args(args, context)
                     when "USER", "PASS", "ACCT"
                       mutate_auth_args(args, context)
                     when "TYPE"
                       context.prng.choice(["A", "I", "E", "L 8", "X", "0"])
                     else
                       mutate_generic_args(args, context)
                     end

      if mutated_args.empty?
        verb
      else
        "#{verb} #{mutated_args}"
      end
    end

    private def mutate_port_args(args : String, context : Context) : String
      # Standard PORT is h1,h2,h3,h4,p1,p2
      octets = args.split(",")
      if octets.size == 6
        target_idx = context.prng.rand(6)
        octets[target_idx] = context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
        octets.join(",")
      else
        "127,0,0,1,#{context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)},#{context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)}"
      end
    end

    private def mutate_path_args(args : String, context : Context) : String
      case context.prng.rand(4)
      when 0
        "../../../../../../../../etc/passwd"
      when 1
        "../" * context.prng.rand(1..8) + args
      when 2
        args + "\x00.png"
      else
        args + "/" + ("A" * context.prng.rand(64..512))
      end
    end

    private def mutate_auth_args(args : String, context : Context) : String
      case context.prng.rand(3)
      when 0
        args + context.prng.choice(["%s%s%s%n", "' OR '1'='1", "\u202Eadmin"])
      when 1
        "admin" + ("\x00" * context.prng.rand(1..4)) + "root"
      else
        "A" * context.prng.rand(128..1024)
      end
    end

    private def mutate_generic_args(args : String, context : Context) : String
      return context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES) if args.empty?
      case context.prng.rand(3)
      when 0
        context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      when 1
        args + " " + context.prng.choice(Mutators::BoundaryNumbers::BOUNDARIES)
      else
        args * context.prng.rand(2..3)
      end
    end
  end
end
