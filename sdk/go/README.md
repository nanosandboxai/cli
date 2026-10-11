# nanosandbox — Go SDK

A **stdlib-only** Go protocol client for the nanosandbox helper
(`nanosb-protocol` v1.0.0). It speaks NDJSON over a Unix stream socket using
only the Go standard library (`net`, `os`, `encoding/base64`, `fmt`) — no
third-party modules. The Go 1.27 standard library has no `json` package, so the
SDK ships a minimal RFC 8259 JSON value type (`nanosandbox/json.go`).

The client surface mirrors the Python SDK (`sdk/python/nanosandbox/client.py`)
and the driver contract in `sdk/conformance/SPEC.md`.

## Requirements

- Go ≥ 1.27 (uses `net.Dial("unix", ...)`, `os.StartProcess`, and the
  `go test` runner).

## Layout

```
sdk/go/
├── go.mod                 # module github.com/nanosandboxai/nanosandbox/sdk/go
├── README.md
├── nanosandbox/
│   ├── json.go            # minimal JSON value type, parser, serializer
│   ├── conn.go            # NanosbError, Conn, NDJSON line framing
│   ├── client.go          # SandboxClient (stateless, dial-per-call)
│   ├── builders.go        # SandboxBuilder, VolumeBuilder
│   ├── sandbox.go         # Sandbox (lifecycle/exec/observability) + AttachSession
│   └── sandbox_fs.go      # Sandbox fs/storage/secrets/snapshots verbs
├── tests/
│   └── client_test.go     # unit tests + fake NDJSON helper
└── conformance/
    └── run.go             # conformance driver
```

The repo root `go.work` file puts `sdk/go` in a Go workspace so the module is
resolvable from the repository root.

## Usage

```go
import "github.com/nanosandboxai/nanosandbox/sdk/go/nanosandbox"

// Connect to the helper socket (performs the hello handshake).
client, err := nanosandbox.Connect("/path/to/helper.sock")

// Capabilities advertised by the helper.
client.Supports("exec") // true | false

// Create a sandbox with the fluent builder.
builder := nanosandbox.NewSandboxBuilder("alpine:latest")
builder.WithName("demo")
builder.WithResources(2, 512)
builder.PublishTcp(8080, 80)
builder.WithLabel("team", "sdk")
box, err := client.CreateWith(builder)

// Lifecycle.
err = box.Start()
state, err := box.State() // "running"

// Buffered exec.
result, err := box.Exec("echo", []string{"hi"})
// { exit_code: 0, stdout: "hi\n", stderr: "", duration_ms: 1 }

// Streamed exec: opening `ok`, then guest frames until `exit`/`error`.
code, err := box.ExecStream(req, func(ev nanosandbox.JsonValue) {
    event, _ := ev.Str("event")
    if event == "stdout" {
        data, _ := ev.Str("data")
        print(data)
    }
})
// code === 0

// Filesystem.
err = box.FsWrite("/tmp/x", []byte("hello"), false)
data, err := box.FsRead("/tmp/x") // []byte
text, err := box.FsReadToString("/etc/hostname")

// Logs (buffered and follow).
lines, err := box.LogsWith(10, 0, "stdout")
err = box.LogsFollowWith(func(line nanosandbox.JsonValue) {
    data, _ := line.Str("data")
    print(data)
}, 10, 0, "stdout")

// Metrics.
m, err := box.Metrics()
err = box.MetricsStream(100, func(sample nanosandbox.JsonValue) {
    cpu, _ := sample.Num("cpu_percent")
    print(cpu)
})

// Volumes, secrets, snapshots.
vol, err := box.VolumeCreate("data", "/host/volumes/data")
err = box.SecretSet("API_KEY", "s3cr3t")
snap, err := box.SnapshotCreate("")

// Attach: drive console input/resize and read guest events.
session, err := box.AttachSession()
err = session.SendInput([]byte("ls\n"))
err = session.Resize(120, 40)
for {
    ev, err := session.ReadEvents()
    if ev.IsNull() {
        break
    }
    data, _ := ev.Str("data")
    print(data)
}
session.Close()

// Typed errors.
_, err = client.Get("missing")
ne, ok := errors.AsType[*nanosandbox.NanosbError](err)
// ne.Code === "not_found"; ne.IsNotFound() === true
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
go test ./sdk/go/...
```

Conformance driver — runs all 35 scenarios in `sdk/conformance/scenarios/`
against the `nanosb-conformance` harness:

```bash
go run ./sdk/go/conformance/run.go
# NANOSB_CONFORMANCE_BIN=/path/to/nanosb-conformance go run ./sdk/go/conformance/run.go
```

Expected output: `35 passed, 0 failed`, exit code 0.