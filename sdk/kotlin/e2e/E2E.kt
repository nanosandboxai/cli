// Real end-to-end test: drive a live microVM through the nanosandbox runtime.
//
// Opt-in — requires the nanosb-runtime helper, libkrun/gvproxy, and a cached
// image. Enable with NANOSB_E2E=1 (and optionally NANOSB_TEST_IMAGE). Mirrors
// the Rust reference smoke (crates/client/tests/live_conformance.rs).
//
//   NANOSB_E2E=1 java -cp sdk/kotlin/nanosandbox-kotlin.jar nanosandbox.kt.E2EKt

package nanosandbox.kt

import nanosandbox.Json
import nanosandbox.ManagedRuntime
import nanosandbox.SandboxBuilder

fun main() {
    if (System.getenv("NANOSB_E2E") != "1") {
        println("SKIP: set NANOSB_E2E=1 to run the live microVM test")
        return
    }
    if (ManagedRuntime.findRuntimeBin() == null) {
        println("SKIP: nanosb-runtime helper not found")
        return
    }

    val image = System.getenv("NANOSB_TEST_IMAGE") ?: "library/alpine:latest"
    val pid = ProcessHandle.current().pid()
    val name = "sdk-e2e-kotlin-$pid"

    val rt = ManagedRuntime.start()
    try {
        val client = KotlinClient.connect(rt.socket.toString())
        check(client.capabilities().isNotEmpty()) { "no capabilities" }

        val spec = SandboxBuilder(image).withName(name).withResources(2, 1024).build()
        val box = client.create(spec)
        check(box.state() == "running") { "state ${box.state()}" }
        check(client.get(name).getStr("name") == name)

        val out = box.exec("echo", arrayOf("hello-from-live"))
        check(out.getInt("exit_code") == 0L)
        check(out.getStr("stdout").trim() == "hello-from-live")

        box.fsWrite("/tmp/live-conformance", "written-by-live".toByteArray(), false)
        check(box.fsReadToString("/tmp/live-conformance") == "written-by-live")
        check(box.fsExists("/tmp/live-conformance"))
        box.fsMkdir("/tmp/live-conformance-dir", true)
        val stat = box.fsStat("/tmp/live-conformance-dir")
        val inner: Json = if (stat.has("stat")) stat.get("stat") else stat
        check(inner.getBool("is_dir"))

        check(box.logs(10).isNotEmpty())
        check(box.metrics().getInt("disk_used_bytes") > 0)
        check(client.list(true).any { it.getStr("name") == name })

        val streamOut = StringBuilder()
        val req = KtJson.obj()
        req.set("command", KtJson.str("echo"))
        val args = KtJson.arr()
        args.add(KtJson.str("hello-stream"))
        req.set("args", args)
        val code = box.execStream(req) { ev -> if (ev.getStr("event") == "stdout") streamOut.append(ev.getStr("data")) }
        check(code == 0) { "exec_stream code $code" }
        check(streamOut.toString().trim() == "hello-stream") { "stream out $streamOut" }

        val sh = box.shell("echo hello-shell")
        check(sh.getInt("exit_code") == 0L) { "shell exit" }
        check(sh.getStr("stdout").trim() == "hello-shell") { "shell out ${sh.getStr("stdout")}" }

        val session = box.attachSession()
        session.close()

        box.secretSet("LIVE_TOKEN", "s3cr3t")
        val secrets = box.secretList()
        check(secrets.any { it.getStr("key") == "LIVE_TOKEN" })
        check(secrets.all { !it.has("value") || it.get("value").isNull() || it.getStr("value").isEmpty() })
        box.secretRemove("LIVE_TOKEN")

        box.pause()
        check(box.state() == "running")
        box.resume()
        check(box.exec("echo", arrayOf("after-resume")).getStr("stdout").trim() == "after-resume")

        val vol = "vol-e2e-kotlin-$pid"
        box.volumeCreate(vol, rt.dir.resolve("vol-data").toString())
        check(box.volumeList().any { it.getStr("name") == vol })
        box.volumeRemove(vol)

        val snap = box.snapshotCreate(null)
        val snapId = snap.getStr("id")
        check(client.snapshots().any { it.getStr("id") == snapId })
        box.snapshotRestore(snapId, "$name-restored")
        box.snapshotRemove(snapId)
        client.sandbox("$name-restored").remove(true)

        box.stop(true)
        client.sandbox(name).remove(true)
        check(client.list(true).none { it.getStr("name") == name })

        println("PASS kotlin live microVM smoke")
    } finally {
        rt.close()
    }
}