// Real end-to-end test: drive a live microVM through the nanosandbox runtime.
//
// Opt-in — requires the nanosb-runtime helper, libkrun/gvproxy, and a cached
// image. Enable with NANOSB_E2E=1 (and optionally NANOSB_TEST_IMAGE). Mirrors
// the Rust reference smoke (crates/client/tests/live_conformance.rs).
//
//   NANOSB_E2E=1 node --test sdk/typescript/tests/e2e.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { SandboxClient } from "../nanosandbox/index.mjs";
import { ManagedRuntime, findRuntimeBin } from "../nanosandbox/runtime.mjs";

const IMAGE = process.env.NANOSB_TEST_IMAGE || "library/alpine:latest";
const ENABLED = process.env.NANOSB_E2E === "1";

test("live microVM smoke", { skip: ENABLED ? false : "set NANOSB_E2E=1 to run" }, async () => {
  assert.ok(findRuntimeBin(), "nanosb-runtime helper not found");

  const name = `sdk-e2e-${process.pid}`;
  const rt = await ManagedRuntime.start();
  try {
    const client = await SandboxClient.connect(rt.socket);
    assert.ok(client.capabilities().length > 0);

    const box = await client.create({
      image: IMAGE,
      name,
      cpus: 2,
      memory_mb: 1024,
      detached: true,
    });
    assert.equal(await box.state(), "running");

    const info = await client.get(name);
    assert.equal(info.name, name);
    assert.equal(info.state, "running");

    const out = await box.exec("echo", ["hello-from-live"]);
    assert.equal(out.exit_code, 0);
    assert.equal(out.stdout.trim(), "hello-from-live");

    await box.fsWrite("/tmp/live-conformance", Buffer.from("written-by-live"));
    assert.equal(await box.fsReadToString("/tmp/live-conformance"), "written-by-live");
    assert.equal(await box.fsExists("/tmp/live-conformance"), true);
    await box.fsMkdir("/tmp/live-conformance-dir", true);
    const stat = await box.fsStat("/tmp/live-conformance-dir");
    assert.equal((stat.stat || stat).is_dir, true);

    assert.ok((await box.logs(10)).length > 0);
    assert.ok((await box.metrics()).disk_used_bytes > 0);
    assert.ok((await client.list(true)).some((s) => s.name === name));

    // ── exec_stream: streamed stdout + exit code ───────────────────────
    let streamOut = "";
    const code = await box.execStream({ command: "echo", args: ["hello-stream"] }, (ev) => {
      if (ev.event === "stdout") streamOut += ev.data;
    });
    assert.equal(code, 0);
    assert.equal(streamOut.trim(), "hello-stream");

    // ── shell: buffered shell script ───────────────────────────────────
    const sh = await box.shell("echo hello-shell");
    assert.equal(sh.exit_code, 0);
    assert.equal(sh.stdout.trim(), "hello-shell");

    // ── attach: open the console session via the helper ────────────────
    const session = await box.attachSession();
    session.close();

    await box.secretSet("LIVE_TOKEN", "s3cr3t");
    const secrets = await box.secretList();
    assert.ok(secrets.some((s) => s.key === "LIVE_TOKEN"));
    assert.ok(secrets.every((s) => s.value == null || s.value === ""));
    await box.secretRemove("LIVE_TOKEN");

    await box.pause();
    assert.equal(await box.state(), "running");
    await box.resume();
    assert.equal((await box.exec("echo", ["after-resume"])).stdout.trim(), "after-resume");

    const vol = `vol-${process.pid}`;
    await box.volumeCreate(vol, `${rt.dir}/vol-data`);
    assert.ok((await box.volumeList()).some((v) => v.name === vol));
    await box.volumeRemove(vol);

    const snap = await box.snapshotCreate();
    assert.ok((await client.snapshots()).some((s) => s.id === snap.id));
    await box.snapshotRestore(snap.id, `${name}-restored`);
    await box.snapshotRemove(snap.id);
    await client.sandbox(`${name}-restored`).remove(true);

    await box.stop(true);
    await client.sandbox(name).remove(true);
    assert.ok(!(await client.list(true)).some((s) => s.name === name));
  } finally {
    await rt.close();
  }
});