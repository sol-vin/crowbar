require "file_utils"
require "../buffer"

module Crowbar::Minimizer
  # Anomaly-preserving test case minimizer and delta debugger.
  # Employs hierarchical delta debugging (bisection chunk slicing, line trimming,
  # and byte simplification) while strictly preserving syntax anomalies such as
  # duplicate keys, malformed grammar boundaries, and protocol discrepancies.
  class Reducer
    property command : String?
    property predicate : Proc(Buffer, Bool)?
    property match_regex : Regex?
    property timeout_ms : Int32
    property progress_callback : Proc(Int32, Int32, Int32, Nil)?

    def initialize(
      @command : String? = nil,
      @predicate : Proc(Buffer, Bool)? = nil,
      @match_regex : Regex? = nil,
      @timeout_ms : Int32 = 1000,
      @progress_callback : Proc(Int32, Int32, Int32, Nil)? = nil,
    )
    end

    # Tests whether a candidate buffer still reproduces the failure predicate
    def test_candidate(candidate : Buffer) : Bool
      return false if candidate.empty?

      # 1. Custom in-memory predicate
      if pred = @predicate
        return pred.call(candidate)
      end

      # 2. External command execution
      cmd_str = @command
      return false unless cmd_str

      run_command_predicate(cmd_str, candidate)
    rescue
      false
    end

    private def run_command_predicate(cmd_str : String, candidate : Buffer) : Bool
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      status : Process::Status? = nil
      timed_out = false

      if cmd_str.includes?("@@")
        # File argument substitution
        temp_file = File.tempfile("crowbar_shrink")
        temp_path = temp_file.path
        begin
          File.write(temp_path, candidate.to_slice)
          expanded_cmd = cmd_str.gsub("@@", temp_path)

          proc = Process.new(
            expanded_cmd,
            shell: true,
            output: stdout_io,
            error: stderr_io
          )

          ch = Channel(Process::Status).new
          spawn do
            ch.send(proc.wait)
          end

          select
          when st = ch.receive
            status = st
          when timeout(@timeout_ms.milliseconds)
            proc.terminate rescue nil
            timed_out = true
          end
        ensure
          temp_file.delete rescue nil
        end
      else
        # STDIN pipe injection
        in_io = IO::Memory.new(candidate.to_slice)
        proc = Process.new(
          cmd_str,
          shell: true,
          input: in_io,
          output: stdout_io,
          error: stderr_io
        )

        ch = Channel(Process::Status).new
        spawn do
          ch.send(proc.wait)
        end

        select
        when st = ch.receive
          status = st
        when timeout(@timeout_ms.milliseconds)
          proc.terminate rescue nil
          timed_out = true
        end
      end

      return false if timed_out || status.nil?

      if regex = @match_regex
        out_combined = stdout_io.to_s + "\n" + stderr_io.to_s
        out_combined.matches?(regex)
      else
        # Standard crash / failure condition: non-zero exit code
        status.exit_code != 0
      end
    end

    # Core reduction loop: reduces input buffer down to minimal reproducer
    def reduce(input : Buffer) : Buffer
      unless test_candidate(input)
        raise ArgumentError.new("Initial input does not satisfy failure predicate")
      end

      current = input.clone
      iteration = 0
      report_progress(iteration, current.size, input.size)

      # Phase 1: Binary Chunk Bisection (Hierarchical Delta Debugging - DDMIN)
      k = 2
      while k <= current.size && current.size > 1
        chunk_size = (current.size.to_f64 / k).ceil.to_i
        reduced_in_pass = false

        # Complement test: try removing each chunk
        (0...k).each do |chunk_idx|
          start_idx = chunk_idx * chunk_size
          end_idx = [start_idx + chunk_size, current.size].min
          next if start_idx >= current.size || (end_idx - start_idx) <= 0

          # Build candidate excluding chunk [start_idx...end_idx]
          cand_bytes = Bytes.new(current.size - (end_idx - start_idx))
          if start_idx > 0
            cand_bytes[0...start_idx].copy_from(current[0...start_idx].to_slice)
          end
          if end_idx < current.size
            cand_bytes[start_idx..].copy_from(current[end_idx..].to_slice)
          end

          candidate = Buffer.new(cand_bytes)
          iteration += 1

          if test_candidate(candidate)
            current = candidate
            report_progress(iteration, current.size, input.size)
            k = [k - 1, 2].max
            reduced_in_pass = true
            break
          end
        end

        next if reduced_in_pass

        # Subset test: try keeping only this chunk if k > 2
        if k > 2
          (0...k).each do |chunk_idx|
            start_idx = chunk_idx * chunk_size
            end_idx = [start_idx + chunk_size, current.size].min
            next if start_idx >= current.size || (end_idx - start_idx) <= 0

            candidate = Buffer.new(current[start_idx...end_idx].to_slice)
            iteration += 1

            if test_candidate(candidate)
              current = candidate
              report_progress(iteration, current.size, input.size)
              k = 2
              reduced_in_pass = true
              break
            end
          end

          next if reduced_in_pass
        end

        # Increase granularity
        if k < current.size
          k = [k * 2, current.size].min
        else
          break
        end
      end

      # Phase 2: Delimiter / Line Slicing
      if current.to_s.includes?("\n")
        lines = current.to_s.split("\n")
        if lines.size > 1
          idx = lines.size - 1
          while idx >= 0
            cand_lines = lines.dup
            cand_lines.delete_at(idx)
            candidate = Buffer.new(cand_lines.join("\n"))
            iteration += 1

            if test_candidate(candidate)
              lines = cand_lines
              current = candidate
              report_progress(iteration, current.size, input.size)
            end
            idx -= 1
          end
        end
      end

      # Phase 3: Byte Simplification (Zeroing / Printable Normalization)
      (0...current.size).each do |b_idx|
        original_byte = current[b_idx]
        next if original_byte == 0_u8

        # Try zeroing
        current[b_idx] = 0_u8
        iteration += 1
        if test_candidate(current)
          report_progress(iteration, current.size, input.size)
          next
        end

        # Try space (0x20)
        if original_byte != 0x20_u8
          current[b_idx] = 0x20_u8
          iteration += 1
          if test_candidate(current)
            report_progress(iteration, current.size, input.size)
            next
          end
        end

        # Revert if neither zeroing nor spacing preserved predicate
        current[b_idx] = original_byte
      end

      current
    end

    private def report_progress(iter : Int32, cur_size : Int32, orig_size : Int32)
      if cb = @progress_callback
        cb.call(iter, cur_size, orig_size)
      end
    end
  end
end
