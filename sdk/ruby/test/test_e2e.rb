# frozen_string_literal: true

# Real end-to-end test: drive a live microVM through the nanosandbox runtime.
#
# Opt-in — requires the nanosb-runtime helper, libkrun/gvproxy, and a cached
# image. Enable with NANOSB_E2E=1 (and optionally NANOSB_TEST_IMAGE). Mirrors
# the Rust reference smoke (crates/client/tests/live_conformance.rs).
#
#   NANOSB_E2E=1 ruby -I sdk/ruby/lib sdk/ruby/test/test_e2e.rb

require "minitest/autorun"
require "nanosandbox"
require "nanosandbox/runtime"

class LiveE2ETest < Minitest::Test
  def test_live_microvm_smoke
    skip "set NANOSB_E2E=1 to run the live microVM test" unless ENV["NANOSB_E2E"] == "1"
    skip "nanosb-runtime helper not found" unless Nanosandbox.find_runtime_bin

    image = ENV["NANOSB_TEST_IMAGE"] || "library/alpine:latest"
    name = "sdk-e2e-ruby-#{Process.pid}"

    Nanosandbox::ManagedRuntime.open do |rt|
      client = Nanosandbox::SandboxClient.connect(rt.socket)
      refute_empty client.capabilities

      box = client.create(
        "image" => image, "name" => name, "cpus" => 2, "memory_mb" => 1024, "detached" => true
      )
      assert_equal "running", box.state
      assert_equal name, client.get(name)["name"]

      out = box.exec("echo", ["hello-from-live"])
      assert_equal 0, out["exit_code"]
      assert_equal "hello-from-live", out["stdout"].strip

      box.fs_write("/tmp/live-conformance", "written-by-live")
      assert_equal "written-by-live", box.fs_read_to_string("/tmp/live-conformance")
      assert box.fs_exists("/tmp/live-conformance")
      box.fs_mkdir("/tmp/live-conformance-dir", true)
      stat = box.fs_stat("/tmp/live-conformance-dir")
      stat = stat["stat"] || stat
      assert stat["is_dir"]

      refute_empty box.logs(10)
      assert box.metrics["disk_used_bytes"].positive?
      assert_includes client.list(true).map { |s| s["name"] }, name

      box.secret_set("LIVE_TOKEN", "s3cr3t")
      secrets = box.secret_list
      assert_includes secrets.map { |s| s["key"] }, "LIVE_TOKEN"
      assert(secrets.all? { |s| s["value"].nil? || s["value"] == "" })
      box.secret_remove("LIVE_TOKEN")

      box.pause
      assert_equal "running", box.state
      box.resume
      assert_equal "after-resume", box.exec("echo", ["after-resume"])["stdout"].strip

      vol = "vol-e2e-ruby"
      box.volume_create(vol, File.join(rt.dir, "vol-data"))
      assert_includes box.volume_list.map { |v| v["name"] }, vol
      box.volume_remove(vol)

      snap = box.snapshot_create
      assert_includes client.snapshots.map { |s| s["id"] }, snap["id"]
      box.snapshot_restore(snap["id"], "#{name}-restored")
      box.snapshot_remove(snap["id"])
      client.sandbox("#{name}-restored").remove(true)

      box.stop(true)
      client.sandbox(name).remove(true)
      refute_includes client.list(true).map { |s| s["name"] }, name
    end
  end
end