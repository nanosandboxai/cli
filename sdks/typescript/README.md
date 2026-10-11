# nanosandbox — TypeScript/Node SDK

A **stdlib-only** Node protocol client for the nanosandbox helper
(`nanosb-protocol` v1.0.0). It speaks NDJSON over a Unix stream socket using
only built-in modules (`node:net`, `node:test`, `node:fs`,
`node:child_process`) — no npm dependencies.

The client surface mirrors the Python SDK (`sdks/python/nanosandbox/client.py`)
and the driver contract in `sdks/conformance/SPEC.md`.

## Requirements

- Node.js ≥ 24 (uses `node:net` Unix sockets and the `node:test` runner).
- ESM (`"type": "module"` in `package.json`; sources are `.mjs`).

## Install

The SDK is a plain directory — copy it or add it to your project:

```bash
cp -r sdks/typescript/nanosandbox ./vendor/nanosandbox
```

or import it directly from the repo:

```js
import { SandboxClient } from "./sdks/typescript/nanosandbox/index.mjs";
```

## Usage

```js
import { SandboxClient, SandboxBuilder } from "nanosandbox";

// Connect to the helper socket (performs the hello handshake).
const client = await SandboxClient.connect("/path/to/helper.sock");

// Capabilities advertised by the helper.
client.supports("exec"); // true | false

// Create a sandbox with the fluent builder.
const spec = new SandboxBuilder("alpine:latest")
  .withName("demo")
  .withResources(2, 512)
  .publishTcp(8080, 80)
  .withLabel("team", "sdk")
  .build();
const box = await client.create(spec);

// Lifecycle.
await box.start();
const state = await box.state(); // "running"

// Buffered exec.
const result = await box.exec("echo", ["hi"]);
// { exit_code: 0, stdout: "hi\n", stderr: "", duration_ms: 1 }

// Streamed exec: opening `ok`, then guest frames until `exit`/`error`.
const code = await box.execStream({ command: "echo", args: ["hi"] }, (ev) => {
  if (ev.event === "stdout") process.stdout.write(ev.data);
});
// code === 0

// Filesystem.
await box.fsWrite("/tmp/x", Buffer.from("hello"));
const bytes = await box.fsRead("/tmp/x"); // Buffer
const text = await box.fsReadToString("/etc/hostname");

// Logs (buffered and follow).
const lines = await box.logsWith(10, 0, "stdout");
await box.logsFollowWith((line) => console.log(line.data), 10, 0, "stdout");

// Metrics.
const m = await box.metrics();
await box.metricsStream(100, (sample) => console.log(sample.cpu_percent));

// Volumes, secrets, snapshots.
await box.volumeCreate("data", "/host/volumes/data");
await box.secretSet("API_KEY", "s3cr3t");
const snap = await box.snapshotCreate();

// Attach: drive console input/resize and read guest events.
const session = await box.attachSession();
await session.sendInput(Buffer.from("ls\n"));
await session.resize(120, 40);
let ev;
while ((ev = await session.readEvents()) !== null) {
  if (ev.event === "stdout") process.stdout.write(ev.data);
}
session.close();

// Typed errors.
try {
  await client.get("missing");
} catch (e) {
  e.code; // "not_found"
  e.isNotFound(); // true
}
```

Every call dials a fresh connection and re-negotiates the `hello` handshake
(stateless, mirroring the Python SDK). Streaming verbs (`exec_stream`,
`attach`, `logs` with `follow`, `metrics_stream`, `fs_write_stream`) hold one
connection for the duration of the stream: an opening `ok` ack, then frames
until the terminal frame (`guest exit/error` or `event done`).

## Testing

Unit tests exercise the client against an in-process fake NDJSON helper on a
temp Unix socket:

```bash
node --test sdks/typescript/tests
```

Conformance driver — runs all 35 scenarios in `sdks/conformance/scenarios/`
against the `nanosb-conformance` harness:

```bash
node sdks/typescript/conformance/run.mjs
# NANOSB_CONFORMANCE_BIN=/path/to/nanosb-conformance node sdks/typescript/conformance/run.mjs
```

Expected output: `35 passed, 0 failed`, exit code 0.

## Layout

```
sdks/typescript/
├── package.json            # ESM, no dependencies
├── README.md
├── nanosandbox/
│   ├── index.mjs           # public entry point
│   ├── client.mjs          # SandboxClient (stateless, dial-per-call)
│   ├── conn.mjs            # NanosbError, Conn, NDJSON line framing
│   ├── builders.mjs        # SandboxBuilder, VolumeBuilder
│   ├── sandbox.mjs         # Sandbox (lifecycle/exec/observability) + AttachSession
│   └── sandbox-fs.mjs      # Sandbox fs/storage/secrets/snapshots verbs
├── tests/
│   └── client.test.mjs     # unit tests + fake NDJSON helper
└── conformance/
    └── run.mjs             # conformance driver
```