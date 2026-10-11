# nanosandbox — Kotlin SDK

A **Kotlin** protocol client for the nanosandbox helper (`nanosb-protocol`
v1.0.0). It is a Kotlin facade over the Java SDK (`sdks/java`): the Java SDK
speaks NDJSON over a Unix stream socket using only the JDK, and the Kotlin
facade (`nanosandbox.kt`) re-exposes its surface with Kotlin-idiomatic naming
and nullable parameters. The conformance driver mirrors
`sdks/java/conformance/Run.java` and the driver contract in
`sdks/conformance/SPEC.md`.

## Requirements

- JDK 21+ (for `javac`/`jar` and the runtime).
- Kotlin compiler 2.x (`kotlinc`), e.g. Homebrew's `kotlin` formula.

## Layout

```
sdks/kotlin/
├── build.sh                          # javac the Java SDK + shim, kotlinc the Kotlin, merge into one jar
├── README.md
├── src/nanosandbox/
│   ├── KtJson.java                   # Java shim: Json factories under Kotlin-resolvable names
│   ├── KotlinClient.kt               # Kotlin facade: stateless client (dial-per-call)
│   └── KotlinSandbox.kt              # Kotlin facade: sandbox handle (lifecycle/exec/fs/obs)
├── src/test/nanosandbox/
│   └── SmokeTest.kt                  # smoke test: KtJson round-trip + facade vs a fake NDJSON helper
└── conformance/
    └── Run.kt                        # conformance driver (runs all 35 scenarios)
```

### Why `KtJson.java`?

Kotlin cannot call `Json.object()` directly: a Java static method named
`object` breaks the Kotlin compiler's companion-object synthesis for the whole
class (kotlinc 2.4.21), so every static factory on `Json` becomes unresolvable
from Kotlin. `KtJson` re-exposes the factories (`obj`, `arr`, `str`, `bool`,
`num`, `nul`, `parse`) under names Kotlin can resolve; the facade and driver
use those. `Json` is still used as a type throughout.

## Usage

```kotlin
import nanosandbox.kt.KotlinClient
import nanosandbox.kt.KotlinSandbox

// Connect to the helper socket (performs the hello handshake).
val client = KotlinClient.connect("/path/to/helper.sock")

// Capabilities advertised by the helper.
client.supports("exec") // true | false

// Create a sandbox from a spec object (build it with the Java SDK's Json).
val spec = KtJson.obj()
spec.set("image", KtJson.str("alpine:latest"))
spec.set("name", KtJson.str("demo"))
val box = client.create(spec)

// Lifecycle.
box.start()
val state = box.state() // "running"

// Buffered exec.
val result = box.exec("echo", arrayOf("hi"))
// { exit_code: 0, stdout: "hi\n", stderr: "", duration_ms: 1 }

// Streamed exec: opening `ok`, then guest frames until `exit`/`error`.
val code = box.execStream(KtJson.obj()) { ev ->
    if (ev.getStr("event") == "stdout") {
        print(ev.getStr("data"))
    }
}

// Filesystem.
box.fsWrite("/tmp/x", "hello".toByteArray(), false)
val data = box.fsRead("/tmp/x")
val text = box.fsReadToString("/etc/hostname")

// Logs (follow) and metrics (stream).
box.logsFollowWith({ line -> print(line.getStr("data")) }, 10, 0, "stdout")
box.metricsStream(100) { sample -> println(sample.get("cpu_percent").asNumber()) }

// Volumes, secrets, snapshots.
val vol = box.volumeCreate("data", "/host/volumes/data")
box.secretSet("API_KEY", "s3cr3t")
val snap = box.snapshotCreate("")

// Typed errors.
try {
    client.get("missing")
} catch (e: NanosbError) {
    e.code()       // "not_found"
    e.isNotFound() // true
}
```

Every call dials a fresh connection and re-negotiates the `hello` handshake
(stateless, mirroring the Java/Python/Go SDKs). Streaming verbs
(`exec_stream`, `attach`, `logs` with `follow`, `metrics_stream`,
`fs_write_stream`) hold one connection for the duration of the stream: an
opening `ok` ack, then frames until the terminal frame (`guest exit/error` or
`event done`).

## Building

```bash
bash sdks/kotlin/build.sh
```

This produces `sdks/kotlin/nanosandbox-kotlin.jar` (self-contained: Kotlin
runtime + Kotlin facade + Java SDK classes).

## Testing

Smoke test — exercises the `KtJson` shim and the facade against an in-process
fake NDJSON helper on a temp Unix socket:

```bash
java -cp sdks/kotlin/nanosandbox-kotlin.jar nanosandbox.kt.SmokeTestKt
# expected: all tests passed, exit code 0
```

Conformance driver — runs all 35 scenarios in `sdks/conformance/scenarios/`
against the `nanosb-conformance` harness:

```bash
java -cp sdks/kotlin/nanosandbox-kotlin.jar nanosandbox.kt.RunKt
# NANOSB_CONFORMANCE_BIN=/path/to/nanosb-conformance \
#   java -cp sdks/kotlin/nanosandbox-kotlin.jar nanosandbox.kt.RunKt
```

Run from the repository root (the driver resolves `sdks/conformance/scenarios`
and `target/debug/nanosb-conformance` relative to the working directory).
Expected output: `35 passed, 0 failed`, exit code 0.