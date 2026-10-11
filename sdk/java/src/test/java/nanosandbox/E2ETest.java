package nanosandbox;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.Test;

/**
 * Real end-to-end test: drive a live microVM through the nanosandbox runtime.
 *
 * <p>Opt-in — requires the nanosb-runtime helper, libkrun/gvproxy, and a cached
 * image. Enable with NANOSB_E2E=1 (and optionally NANOSB_TEST_IMAGE). Mirrors
 * the Rust reference smoke (crates/client/tests/live_conformance.rs).
 *
 * <pre>NANOSB_E2E=1 mvn -f sdk/java/pom.xml test -Dtest=E2ETest</pre>
 */
class E2ETest {

  @Test
  void liveMicroVmSmoke() throws Exception {
    Assumptions.assumeTrue("1".equals(System.getenv("NANOSB_E2E")), "set NANOSB_E2E=1 to run");
    Assumptions.assumeTrue(ManagedRuntime.findRuntimeBin() != null, "nanosb-runtime not found");

    String image = System.getenv().getOrDefault("NANOSB_TEST_IMAGE", "library/alpine:latest");
    String name = "sdk-e2e-java-" + ProcessHandle.current().pid();

    try (ManagedRuntime rt = ManagedRuntime.start()) {
      SandboxClient client = SandboxClient.connect(rt.socket.toString());
      assertFalse(client.capabilities().isEmpty());

      Sandbox box = client.createWith(new SandboxBuilder(image).withName(name).withResources(2, 1024));
      assertEquals("running", box.state());
      assertEquals(name, client.get(name).getStr("name"));

      Json out = box.exec("echo", new String[] {"hello-from-live"});
      assertEquals(0, out.getInt("exit_code"));
      assertEquals("hello-from-live", out.getStr("stdout").trim());

      box.fsWrite("/tmp/live-conformance", "written-by-live".getBytes(), false);
      assertEquals("written-by-live", box.fsReadToString("/tmp/live-conformance"));
      assertTrue(box.fsExists("/tmp/live-conformance"));
      box.fsMkdir("/tmp/live-conformance-dir", true);
      Json stat = box.fsStat("/tmp/live-conformance-dir");
      Json inner = stat.has("stat") ? stat.get("stat") : stat;
      assertTrue(inner.getBool("is_dir"));

      assertFalse(box.logs(10).isEmpty());
      assertTrue(box.metrics().getInt("disk_used_bytes") > 0);
      assertTrue(names(client.list(true)).contains(name));

      box.secretSet("LIVE_TOKEN", "s3cr3t");
      List<Json> secrets = box.secretList();
      assertTrue(secrets.stream().anyMatch(s -> "LIVE_TOKEN".equals(s.getStr("key"))));
      for (Json s : secrets) {
        if (s.has("value") && !s.get("value").isNull()) {
          assertTrue(s.getStr("value").isEmpty(), "secret value must be redacted");
        }
      }
      box.secretRemove("LIVE_TOKEN");

      box.pause();
      assertEquals("running", box.state());
      box.resume();
      assertEquals("after-resume", box.exec("echo", new String[] {"after-resume"}).getStr("stdout").trim());

      String vol = "vol-e2e-java-" + ProcessHandle.current().pid();
      box.volumeCreate(vol, rt.dir.resolve("vol-data").toString());
      assertTrue(names(box.volumeList()).contains(vol));
      box.volumeRemove(vol);

      Json snap = box.snapshotCreate(null);
      String snapId = snap.getStr("id");
      assertTrue(client.snapshots().stream().anyMatch(s -> snapId.equals(s.getStr("id"))));
      box.snapshotRestore(snapId, name + "-restored");
      box.snapshotRemove(snapId);
      client.sandbox(name + "-restored").remove(true);

      box.stop(true);
      client.sandbox(name).remove(true);
      assertFalse(names(client.list(true)).contains(name));
    }
  }

  private static List<String> names(List<Json> list) {
    return list.stream().map(j -> j.getStr("name")).toList();
  }
}