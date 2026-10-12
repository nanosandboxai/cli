// Managed nanosandbox runtime: locate the helper, spawn it, and connect.
//
// Lets a TypeScript SDK user manage real sandboxes without starting the helper
// by hand. The helper (`nanosb-runtime serve`) owns the microVM lifecycle; SDK
// calls are protocol messages over its Unix socket.
//
//   const rt = await ManagedRuntime.start();
//   const client = await SandboxClient.connect(rt.socket);
//   const box = await client.create({ image: "library/alpine:latest", name: "demo" });
//   await rt.close();

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

export function findRuntimeBin() {
  const env = process.env.NANOSB_RUNTIME_BIN;
  if (env && existsSync(env)) return env;
  const home = process.env.NANOSB_HOME || join(homedir(), ".nanosandbox");
  const bundled = join(home, "bin", "nanosb-runtime");
  if (existsSync(bundled)) return bundled;
  const repo = join(__dirname, "..", "..", "..");
  const dev = join(repo, "target", "debug", "nanosb-runtime");
  if (existsSync(dev)) return dev;
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class ManagedRuntime {
  constructor(proc, dir, socket) {
    this.proc = proc;
    this.dir = dir;
    this.socket = socket;
  }

  static async start(waitMs = 15000) {
    const bin = findRuntimeBin();
    if (!bin) {
      throw new Error(
        "nanosb-runtime not found; set NANOSB_RUNTIME_BIN or build it " +
          "(cargo build -p nanosb-cli --bin nanosb-runtime --no-default-features --features runtime-host)",
      );
    }
    const dir = await mkdtemp(join(tmpdir(), "nanosb-e2e-"));
    const socket = join(dir, "helper.sock");
    const proc = spawn(bin, ["serve", "--socket", socket], { stdio: "ignore" });
    const deadline = Date.now() + waitMs;
    while (!existsSync(socket)) {
      if (proc.exitCode !== null) {
        await rm(dir, { recursive: true, force: true });
        throw new Error("nanosb-runtime exited before opening its socket");
      }
      if (Date.now() > deadline) {
        proc.kill();
        await rm(dir, { recursive: true, force: true });
        throw new Error("timed out waiting for the helper socket");
      }
      await sleep(50);
    }
    return new ManagedRuntime(proc, dir, socket);
  }

  async close() {
    if (this.proc && this.proc.exitCode === null) {
      this.proc.kill("SIGTERM");
      await new Promise((resolve) => {
        const t = setTimeout(() => {
          try {
            this.proc.kill("SIGKILL");
          } catch {}
          resolve();
        }, 5000);
        this.proc.once("exit", () => {
          clearTimeout(t);
          resolve();
        });
      });
    }
    await rm(this.dir, { recursive: true, force: true });
  }
}