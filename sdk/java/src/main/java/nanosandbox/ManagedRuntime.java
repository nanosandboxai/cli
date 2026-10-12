package nanosandbox;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

/**
 * Managed nanosandbox runtime: locate the helper, spawn it, and connect.
 *
 * <p>Lets a Java SDK user manage real sandboxes without starting the helper by
 * hand. The helper ({@code nanosb-runtime serve}) owns the microVM lifecycle;
 * SDK calls are protocol messages over its Unix socket.
 *
 * <pre>{@code
 * try (ManagedRuntime rt = ManagedRuntime.start()) {
 *   SandboxClient client = SandboxClient.connect(rt.socket.toString());
 *   Sandbox box = client.createWith(new SandboxBuilder("library/alpine:latest").withName("demo"));
 *   System.out.println(box.exec("echo", new String[]{"hi"}).getStr("stdout"));
 * }
 * }</pre>
 */
public final class ManagedRuntime implements AutoCloseable {
  private final Process proc;
  public final Path dir;
  public final Path socket;

  private ManagedRuntime(Process proc, Path dir, Path socket) {
    this.proc = proc;
    this.dir = dir;
    this.socket = socket;
  }

  /** Locate the nanosb-runtime helper, in order of preference. */
  public static String findRuntimeBin() {
    String env = System.getenv("NANOSB_RUNTIME_BIN");
    if (env != null && Files.exists(Path.of(env))) {
      return env;
    }
    String home = System.getenv("NANOSB_HOME");
    if (home == null) {
      home = System.getProperty("user.home") + "/.nanosandbox";
    }
    Path bundled = Path.of(home, "bin", "nanosb-runtime");
    if (Files.exists(bundled)) {
      return bundled.toString();
    }
    String path = System.getenv("PATH");
    if (path != null) {
      for (String p : path.split(":")) {
        Path c = Path.of(p, "nanosb-runtime");
        if (Files.isExecutable(c)) {
          return c.toString();
        }
      }
    }
    Path d = Path.of("").toAbsolutePath();
    for (int i = 0; i < 8 && d != null; i++) {
      Path c = d.resolve("target/debug/nanosb-runtime");
      if (Files.exists(c)) {
        return c.toString();
      }
      d = d.getParent();
    }
    return null;
  }

  /** Start the helper on a private socket and wait for it to listen. */
  public static ManagedRuntime start() throws IOException {
    String bin = findRuntimeBin();
    if (bin == null) {
      throw new IOException(
          "nanosb-runtime not found; set NANOSB_RUNTIME_BIN or build it "
              + "(cargo build -p nanosb-cli --bin nanosb-runtime --no-default-features --features runtime-host)");
    }
    Path dir = Files.createTempDirectory("nanosb-e2e-");
    Path socket = dir.resolve("helper.sock");
    Process proc =
        new ProcessBuilder(bin, "serve", "--socket", socket.toString())
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start();
    long deadline = System.currentTimeMillis() + 15_000;
    while (!Files.exists(socket)) {
      if (!proc.isAlive()) {
        deleteTree(dir);
        throw new IOException("nanosb-runtime exited before opening its socket");
      }
      if (System.currentTimeMillis() > deadline) {
        proc.destroyForcibly();
        deleteTree(dir);
        throw new IOException("timed out waiting for the helper socket");
      }
      try {
        Thread.sleep(50);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    }
    return new ManagedRuntime(proc, dir, socket);
  }

  @Override
  public void close() {
    proc.destroy();
    try {
      if (!proc.waitFor(5, TimeUnit.SECONDS)) {
        proc.destroyForcibly();
      }
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
    deleteTree(dir);
  }

  private static void deleteTree(Path dir) {
    if (dir == null || !Files.exists(dir)) {
      return;
    }
    try (Stream<Path> s = Files.walk(dir)) {
      s.sorted(Comparator.reverseOrder())
          .forEach(
              p -> {
                try {
                  Files.deleteIfExists(p);
                } catch (IOException ignored) {
                  // best effort
                }
              });
    } catch (IOException ignored) {
      // best effort
    }
  }
}