# frozen_string_literal: true

# Managed nanosandbox runtime: locate the helper, spawn it, and connect.
#
# Lets a Ruby SDK user manage real sandboxes without starting the helper by
# hand. The helper (`nanosb-runtime serve`) owns the microVM lifecycle; SDK
# calls are protocol messages over its Unix socket.
#
#   Nanosandbox::ManagedRuntime.open do |rt|
#     client = Nanosandbox::SandboxClient.connect(rt.socket)
#     box = client.create("image" => "library/alpine:latest", "name" => "demo")
#     puts box.exec("echo", ["hi"])["stdout"]
#   end

require "tmpdir"
require "fileutils"

module Nanosandbox
  # Locate the nanosb-runtime helper, in order of preference.
  def self.find_runtime_bin
    env = ENV["NANOSB_RUNTIME_BIN"]
    return env if env && File.exist?(env)

    home = ENV["NANOSB_HOME"] || File.join(Dir.home, ".nanosandbox")
    candidate = File.join(home, "bin", "nanosb-runtime")
    return candidate if File.exist?(candidate)

    which = `which nanosb-runtime 2>/dev/null`.strip
    return which unless which.empty?

    repo = File.expand_path("../../../..", __dir__) # lib/nanosandbox/runtime.rb -> repo root
    dev = File.join(repo, "target", "debug", "nanosb-runtime")
    return dev if File.exist?(dev)

    nil
  end

  # A running nanosb-runtime helper on a private socket.
  class ManagedRuntime
    attr_reader :dir, :socket, :pid

    def initialize(binary: nil, wait_secs: 15)
      @binary = binary || Nanosandbox.find_runtime_bin
      raise "nanosb-runtime not found; set NANOSB_RUNTIME_BIN or build it" unless @binary

      @dir = Dir.mktmpdir("nanosb-e2e-")
      @socket = File.join(@dir, "helper.sock")
      @pid = spawn(@binary, "serve", "--socket", @socket, out: File::NULL, err: File::NULL)
      deadline = Time.now + wait_secs
      until File.exist?(@socket)
        raise "timed out waiting for the helper socket" if Time.now > deadline
        raise "nanosb-runtime exited before opening its socket" unless alive?

        sleep 0.05
      end
    end

    def alive?
      Process.kill(0, @pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def close
      begin
        Process.kill("TERM", @pid)
        Process.wait(@pid)
      rescue StandardError
        begin
          Process.kill("KILL", @pid)
        rescue StandardError
          nil
        end
      end
      FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
    end

    def self.open(**kwargs)
      rt = new(**kwargs)
      return rt unless block_given?

      begin
        yield rt
      ensure
        rt.close
      end
    end
  end
end