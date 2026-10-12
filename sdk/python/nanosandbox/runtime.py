"""Managed nanosandbox runtime: locate the helper, spawn it, and connect.

Lets a Python SDK user manage *real* sandboxes without starting the helper by
hand. The helper (`nanosb-runtime serve`) owns the microVM lifecycle; SDK calls
are protocol messages over its Unix socket.

    with ManagedRuntime() as rt:
        client = SandboxClient.connect(rt.socket)
        box = client.create({"image": "library/alpine:latest", "name": "demo"})
        print(box.exec("echo", ["hi"])["stdout"])
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Optional


def find_runtime_bin() -> Optional[str]:
    """Locate the nanosb-runtime helper, in order of preference."""
    env = os.environ.get("NANOSB_RUNTIME_BIN")
    if env and Path(env).exists():
        return env
    home = os.environ.get("NANOSB_HOME") or str(Path.home() / ".nanosandbox")
    candidate = Path(home) / "bin" / "nanosb-runtime"
    if candidate.exists():
        return str(candidate)
    which = shutil.which("nanosb-runtime")
    if which:
        return which
    repo = Path(__file__).resolve().parents[3]
    dev = repo / "target" / "debug" / "nanosb-runtime"
    if dev.exists():
        return str(dev)
    return None


class ManagedRuntime:
    """A running nanosb-runtime helper on a private socket."""

    def __init__(self, binary: Optional[str] = None, wait_secs: float = 15.0) -> None:
        self.binary = binary or find_runtime_bin()
        if not self.binary:
            raise RuntimeError(
                "nanosb-runtime not found; set NANOSB_RUNTIME_BIN or build it "
                "(cargo build -p nanosb-cli --bin nanosb-runtime "
                "--no-default-features --features runtime-host)"
            )
        self.dir = Path(tempfile.mkdtemp(prefix="nanosb-e2e-"))
        self.socket = self.dir / "helper.sock"
        self.proc = subprocess.Popen([self.binary, "serve", "--socket", str(self.socket)])
        deadline = time.monotonic() + wait_secs
        while not self.socket.exists():
            if self.proc.poll() is not None:
                self.close()
                raise RuntimeError("nanosb-runtime exited before opening its socket")
            if time.monotonic() > deadline:
                self.close()
                raise RuntimeError("timed out waiting for the helper socket")
            time.sleep(0.05)

    def close(self) -> None:
        proc = getattr(self, "proc", None)
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        shutil.rmtree(getattr(self, "dir", ""), ignore_errors=True)

    def __enter__(self) -> "ManagedRuntime":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()