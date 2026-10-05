{% if flag?(:windows) %}
  lib LibC
    fun PeekNamedPipe(
      hNamedPipe : HANDLE,
      lpBuffer : Void*,
      nBufferSize : DWORD,
      lpBytesRead : DWORD*,
      lpTotalBytesAvail : DWORD*,
      lpBytesLeftThisMessage : DWORD*,
    ) : BOOL
  end
{% else %}
  lib LibC
    POLLIN = 0x0001_i16

    struct PollFD
      fd : Int32
      events : Int16
      revents : Int16
    end

    fun opal_poll = poll(fds : Void*, nfds : UInt64, timeout : Int32) : Int32
  end
{% end %}

module Crowbar::CLI
  # Low-level platform stream abstraction for non-blocking stdin inspection
  module PlatformIO
    # Checks whether an input IO stream has data available to read without blocking
    def self.has_data?(io : IO) : Bool
      # Handle in-memory streams (for testing and synthetic pipelines)
      if io.is_a?(IO::Memory)
        return io.as(IO::Memory).bytesize > 0
      end

      {% if flag?(:windows) %}
        h = LibC.GetStdHandle(LibC::STD_INPUT_HANDLE)
        if LibC.PeekNamedPipe(h, nil, 0, nil, out avail, nil) != 0
          return avail > 0
        end
        if io.is_a?(IO::FileDescriptor)
          begin
            fd_info = io.as(IO::FileDescriptor).info
            return fd_info.file? && fd_info.size > 0
          rescue
            false
          end
        end
        false
      {% else %}
        if io.is_a?(IO::FileDescriptor)
          begin
            fd_info = io.as(IO::FileDescriptor).info
            return true if fd_info.file? && fd_info.size > 0
          rescue
          end
          pfd = LibC::PollFD.new(fd: io.as(IO::FileDescriptor).fd, events: LibC::POLLIN, revents: 0_i16)
          res = LibC.opal_poll(pointerof(pfd).as(Void*), 1_u64, 50)
          return res > 0 && ((pfd.revents & LibC::POLLIN) != 0)
        end
        false
      {% end %}
    rescue
      false
    end

    # Checks whether an IO stream is connected to an interactive terminal/TTY
    def self.tty?(io : IO) : Bool
      if io.is_a?(IO::FileDescriptor)
        io.as(IO::FileDescriptor).tty?
      else
        false
      end
    rescue
      false
    end
  end
end
