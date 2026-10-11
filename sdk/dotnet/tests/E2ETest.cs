using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;

/// <summary>
/// Real end-to-end test: drive a live microVM through the nanosandbox runtime.
///
/// Opt-in — requires the nanosb-runtime helper, libkrun/gvproxy, and a cached
/// image. Enable with NANOSB_E2E=1 (and optionally NANOSB_TEST_IMAGE). Mirrors
/// the Rust reference smoke (crates/client/tests/live_conformance.rs).
///
///   NANOSB_E2E=1 dotnet test sdk/dotnet --filter E2ETest
/// </summary>
[TestClass]
public class E2ETest {
    [TestMethod]
    public void LiveMicroVmSmoke() {
        if (Environment.GetEnvironmentVariable("NANOSB_E2E") != "1") {
            Assert.Inconclusive("set NANOSB_E2E=1 to run the live microVM test");
        }
        if (ManagedRuntime.findRuntimeBin() == null) {
            Assert.Inconclusive("nanosb-runtime helper not found");
        }

        var image = Environment.GetEnvironmentVariable("NANOSB_TEST_IMAGE") ?? "library/alpine:latest";
        var pid = Process.GetCurrentProcess().Id;
        var name = "sdk-e2e-dotnet-" + pid;

        using var rt = ManagedRuntime.start();
        var client = SandboxClient.connect(rt.Socket);
        Assert.IsTrue(client.capabilities().Count > 0);

        var spec = new SandboxBuilder(image).withName(name).withResources(2, 1024).build();
        var box = client.create(spec);
        Assert.AreEqual("running", box.state().str("state"));
        Assert.AreEqual(name, client.get(name).str("name"));

        var outv = box.exec("echo", new List<String> { "hello-from-live" });
        Assert.AreEqual(0L, outv.intVal("exit_code"));
        Assert.AreEqual("hello-from-live", outv.str("stdout").Trim());

        box.fsWrite("/tmp/live-conformance", Encoding.UTF8.GetBytes("written-by-live"), false);
        Assert.AreEqual("written-by-live", box.fsReadToString("/tmp/live-conformance"));
        Assert.IsTrue(box.fsExists("/tmp/live-conformance"));
        box.fsMkdir("/tmp/live-conformance-dir", true);
        var stat = box.fsStat("/tmp/live-conformance-dir");
        var inner = stat.has("stat") ? stat.get("stat") : stat;
        Assert.IsTrue(inner.boolVal("is_dir"));

        Assert.IsTrue(box.logsWith(10, -1, null).arr("lines").Count > 0);
        Assert.IsTrue(box.metrics().intVal("disk_used_bytes") > 0);
        Assert.IsTrue(Names(client.list(true)).Contains(name));

        box.secretSet("LIVE_TOKEN", "s3cr3t");
        var secrets = box.secretList();
        Assert.IsTrue(secrets.Exists(s => s.str("key") == "LIVE_TOKEN"));
        foreach (var s in secrets) {
            if (s.has("value") && !s.get("value").isNull()) {
                Assert.AreEqual("", s.str("value"), "secret value must be redacted");
            }
        }
        box.secretRemove("LIVE_TOKEN");

        box.pause();
        Assert.AreEqual("running", box.state().str("state"));
        box.resume();
        Assert.AreEqual("after-resume", box.exec("echo", new List<String> { "after-resume" }).str("stdout").Trim());

        var vol = "vol-e2e-dotnet-" + pid;
        box.volumeCreate(vol, Path.Combine(rt.Dir, "vol-data"));
        Assert.IsTrue(Names(box.volumeList()).Contains(vol));
        box.volumeRemove(vol);

        var snap = box.snapshotCreate(null);
        var snapId = snap.str("id");
        Assert.IsTrue(client.snapshots().Exists(s => s.str("id") == snapId));
        box.snapshotRestore(snapId, name + "-restored");
        box.snapshotRemove(snapId);
        client.sandbox(name + "-restored").remove(true);

        box.stop(true);
        client.sandbox(name).remove(true);
        Assert.IsFalse(Names(client.list(true)).Contains(name));
    }

    private static List<String> Names(List<JsonValue> list) {
        var names = new List<String>();
        foreach (var j in list) {
            names.Add(j.str("name"));
        }
        return names;
    }
}