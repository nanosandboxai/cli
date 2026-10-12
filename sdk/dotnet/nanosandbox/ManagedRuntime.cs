using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

/// <summary>
/// Managed nanosandbox runtime: locate the helper, spawn it, and connect.
///
/// Lets a .NET SDK user manage real sandboxes without starting the helper by
/// hand. The helper (<c>nanosb-runtime serve</c>) owns the microVM lifecycle;
/// SDK calls are protocol messages over its Unix socket.
/// </summary>
public sealed class ManagedRuntime : IDisposable {
    public Process Proc { get; }
    public String Dir { get; }
    public String Socket { get; }

    private ManagedRuntime(Process proc, String dir, String socket) {
        Proc = proc;
        Dir = dir;
        Socket = socket;
    }

    /// <summary>Locate the nanosb-runtime helper, in order of preference.</summary>
    public static String findRuntimeBin() {
        var env = Environment.GetEnvironmentVariable("NANOSB_RUNTIME_BIN");
        if (!String.IsNullOrEmpty(env) && File.Exists(env)) {
            return env;
        }
        var home = Environment.GetEnvironmentVariable("NANOSB_HOME")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nanosandbox");
        var bundled = Path.Combine(home, "bin", "nanosb-runtime");
        if (File.Exists(bundled)) {
            return bundled;
        }
        var path = Environment.GetEnvironmentVariable("PATH");
        if (!String.IsNullOrEmpty(path)) {
            foreach (var p in path.Split(Path.PathSeparator)) {
                var c = Path.Combine(p, "nanosb-runtime");
                if (File.Exists(c)) {
                    return c;
                }
            }
        }
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 8 && dir != null; i++) {
            var candidate = Path.Combine(dir, "target", "debug", "nanosb-runtime");
            if (File.Exists(candidate)) {
                return candidate;
            }
            dir = Path.GetDirectoryName(dir);
        }
        return null;
    }

    /// <summary>Start the helper on a private socket and wait for it to listen.</summary>
    public static ManagedRuntime start() {
        var bin = findRuntimeBin();
        if (bin == null) {
            throw new InvalidOperationException(
                "nanosb-runtime not found; set NANOSB_RUNTIME_BIN or build it " +
                "(cargo build -p nanosb-cli --bin nanosb-runtime --no-default-features --features runtime-host)");
        }
        // Keep the path short: a Unix socket path must fit in sun_path (~104).
        var dir = Path.Combine("/tmp", "nanosb-e2e-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(dir);
        var socket = Path.Combine(dir, "helper.sock");
        var psi = new ProcessStartInfo(bin) { UseShellExecute = false };
        psi.ArgumentList.Add("serve");
        psi.ArgumentList.Add("--socket");
        psi.ArgumentList.Add(socket);
        var proc = Process.Start(psi);
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(15);
        while (!File.Exists(socket)) {
            if (proc.HasExited) {
                Directory.Delete(dir, true);
                throw new InvalidOperationException("nanosb-runtime exited before opening its socket");
            }
            if (DateTime.UtcNow > deadline) {
                proc.Kill(true);
                Directory.Delete(dir, true);
                throw new InvalidOperationException("timed out waiting for the helper socket");
            }
            Thread.Sleep(50);
        }
        return new ManagedRuntime(proc, dir, socket);
    }

    public void Dispose() {
        try {
            if (!Proc.HasExited) {
                Proc.Kill(true);
                Proc.WaitForExit(5000);
            }
        } catch {
            // best effort
        }
        try {
            Directory.Delete(Dir, true);
        } catch {
            // best effort
        }
    }
}