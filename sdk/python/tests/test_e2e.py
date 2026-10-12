"""Real end-to-end test: drive a live microVM through the nanosandbox runtime.

Opt-in — requires the nanosb-runtime helper, libkrun/gvproxy, and a cached
image. Enable with NANOSB_E2E=1 (and optionally NANOSB_TEST_IMAGE). Mirrors the
Rust reference smoke (crates/client/tests/live_conformance.rs).

    NANOSB_E2E=1 python3 -m unittest sdk/python/tests/test_e2e.py
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from nanosandbox import SandboxClient  # noqa: E402
from nanosandbox.runtime import ManagedRuntime, find_runtime_bin  # noqa: E402

_IMAGE = os.environ.get("NANOSB_TEST_IMAGE", "library/alpine:latest")
_ENABLED = os.environ.get("NANOSB_E2E") == "1"


@unittest.skipUnless(_ENABLED, "set NANOSB_E2E=1 to run the live microVM test")
class LiveE2ETest(unittest.TestCase):
    def test_live_microvm_smoke(self) -> None:
        if find_runtime_bin() is None:
            self.skipTest("nanosb-runtime helper not found")

        name = f"sdk-e2e-{os.getpid()}"
        with ManagedRuntime() as rt:
            client = SandboxClient.connect(str(rt.socket))
            self.assertTrue(client.capabilities())

            sandbox = client.create(
                {"image": _IMAGE, "name": name, "cpus": 2, "memory_mb": 1024, "detached": True}
            )
            self.assertEqual(sandbox.state(), "running")

            info = client.get(name)
            self.assertEqual(info["name"], name)
            self.assertEqual(info["state"], "running")

            out = sandbox.exec("echo", ["hello-from-live"])
            self.assertEqual(out["exit_code"], 0)
            self.assertEqual(out["stdout"].strip(), "hello-from-live")

            sandbox.fs_write("/tmp/live-conformance", b"written-by-live")
            self.assertEqual(sandbox.fs_read_to_string("/tmp/live-conformance"), "written-by-live")
            self.assertTrue(sandbox.fs_exists("/tmp/live-conformance"))
            sandbox.fs_mkdir("/tmp/live-conformance-dir", True)
            stat = sandbox.fs_stat("/tmp/live-conformance-dir")
            self.assertTrue(stat.get("stat", stat).get("is_dir"))

            self.assertTrue(sandbox.logs(10))
            self.assertGreater(sandbox.metrics()["disk_used_bytes"], 0)
            self.assertIn(name, [s["name"] for s in client.list(True)])

            stream_stdout = []
            code = sandbox.exec_stream({"command": "echo", "args": ["hello-stream"]},
                                       lambda ev: stream_stdout.append(ev.get("data", "")) if ev.get("event") == "stdout" else None)
            self.assertEqual(code, 0)
            self.assertEqual("".join(stream_stdout).strip(), "hello-stream")

            sh = sandbox.shell("echo hello-shell")
            self.assertEqual(sh["exit_code"], 0)
            self.assertEqual(sh["stdout"].strip(), "hello-shell")

            session = sandbox.attach_session()
            session.close()

            sandbox.secret_set("LIVE_TOKEN", "s3cr3t")
            secrets = sandbox.secret_list()
            self.assertIn("LIVE_TOKEN", [s["key"] for s in secrets])
            self.assertTrue(all(s.get("value") in (None, "") for s in secrets))
            sandbox.secret_remove("LIVE_TOKEN")

            sandbox.pause()
            self.assertEqual(sandbox.state(), "running")
            sandbox.resume()
            self.assertEqual(sandbox.exec("echo", ["after-resume"])["stdout"].strip(), "after-resume")

            vol = f"vol-{os.getpid()}"
            sandbox.volume_create(vol, str(rt.dir / "vol-data"))
            self.assertIn(vol, [v["name"] for v in sandbox.volume_list()])
            sandbox.volume_remove(vol)

            snap = sandbox.snapshot_create()
            self.assertIn(snap["id"], [s["id"] for s in client.snapshots()])
            sandbox.snapshot_restore(snap["id"], f"{name}-restored")
            sandbox.snapshot_remove(snap["id"])
            client.sandbox(f"{name}-restored").remove(True)

            sandbox.stop(True)
            client.sandbox(name).remove(True)
            self.assertNotIn(name, [s["name"] for s in client.list(True)])


if __name__ == "__main__":
    unittest.main()