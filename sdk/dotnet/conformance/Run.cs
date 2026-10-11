// Run.cs — conformance driver entry point.
//
// Runs every scenario in `sdk/conformance/scenarios/` against the
// `nanosb-conformance` harness and evaluates the scenario `assert` blocks per
// `sdk/conformance/SPEC.md`. Exits non-zero if any scenario fails.
//
// Usage:
//     dotnet run --project sdk/dotnet/conformance
//     NANOSB_CONFORMANCE_BIN=/path/to/nanosb-conformance dotnet run --project sdk/dotnet/conformance

using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System;

class Run {
    public static int READY_TIMEOUT_MS = 15000;
    public static int RECV_TIMEOUT_MS = 10000;

    public static void Main(String[] args) {
        String binPath = findBinary();
        String scenariosDir = repoRoot() + "/sdk/conformance/scenarios";
        List<String> files = new List<String>();
        String[] entries = Directory.GetFileSystemEntries(scenariosDir);
        for (int i = 0; i < entries.Length; i++) {
            if (entries[i].EndsWith(".json")) {
                files.Add(entries[i]);
            }
        }
        if (files.Count == 0) {
            Console.Error.WriteLine("error: no scenarios found in " + scenariosDir);
            System.Environment.Exit(1);
        }
        sortStrings(files);

        int passed = 0;
        int failed = 0;
        for (int i = 0; i < files.Count; i++) {
            String scenarioFile = files[i];
            String sid = "";
            try {
                JsonValue scenario = readScenario(scenarioFile);
                sid = scenario.str("id");
            } catch (Exception e) {
                failed++;
                Console.WriteLine("FAIL " + scenarioFile + ": " + e.Message);
                continue;
            }
            String[] result = runScenario(binPath, scenarioFile);
            if (result[0].Equals("ok")) {
                passed++;
                Console.WriteLine("PASS " + sid);
            } else {
                failed++;
                Console.WriteLine("FAIL " + sid + ": " + result[1]);
            }
        }

        Console.WriteLine("");
        Console.WriteLine(passed + " passed, " + failed + " failed");
        if (failed > 0) {
            System.Environment.Exit(1);
        }
    }

    public static String[] runScenario(String binPath, String scenarioFile) {
        JsonValue scenario;
        try {
            scenario = readScenario(scenarioFile);
        } catch (Exception e) {
            return new String[]{"fail", "cannot read scenario: " + e.Message};
        }
        JsonValue assertBlock = scenario.has("assert") ? scenario.get("assert") : JsonValue.makeObject();

        ProcessStartInfo psi = new ProcessStartInfo(binPath, new String[]{"serve", "--scenario", scenarioFile});
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        Process ph = Process.Start(psi);

        String sock = "";
        try {
            String line = ph.StandardOutput.ReadLine();
            if (line == null || !line.StartsWith("READY ")) {
                return new String[]{"fail", "harness did not print READY: " + (line == null ? "" : line)};
            }
            sock = line.Substring(6);

            SandboxClient client = SandboxClient.connect(sock);
            DriverState state = new DriverState();
            Conn writeConn = null;
            String driveError = null;
            try {
                List<JsonValue> steps = scenario.has("steps") ? scenario.arr("steps") : new List<JsonValue>();
                for (int i = 0; i < steps.Count; i++) {
                    JsonValue step = steps[i];
                    JsonValue expect = step.has("expect") ? step.get("expect") : JsonValue.makeObject();
                    bool hasTimeout = step.has("timeout_ms");
                    bool expectsTimeout = assertBlock.has("expects_timeout") && assertBlock.boolVal("expects_timeout");
                    if (expectsTimeout && hasTimeout) {
                        Conn conn = new Conn(sock);
                        conn.setReadTimeout(RECV_TIMEOUT_MS);
                        JsonValue resp = conn.recv();
                        conn.close();
                        state.timeoutCode = resp.str("code");
                        break;
                    }
                    String etype = expect.str("type");
                    if (etype.Equals("fs_data")) {
                        if (writeConn == null) {
                            driveError = "fs_data step without an open write stream";
                            break;
                        }
                        JsonValue body = JsonValue.makeObject();
                        body.put("type", JsonValue.of("fs_data"));
                        body.put("data_base64", JsonValue.of(expect.str("data_base64")));
                        body.put("eof", JsonValue.of(expect.boolVal("eof")));
                        writeConn.call(body);
                        state.chunksAcked++;
                        continue;
                    }
                    if (etype.Equals("fs_write_stream")) {
                        writeConn = new Conn(sock);
                        JsonValue req = JsonValue.makeObject();
                        req.put("type", JsonValue.of("fs_write_stream"));
                        req.put("name", JsonValue.of(expect.str("name")));
                        req.put("path", JsonValue.of(expect.str("path")));
                        writeConn.send(req);
                        JsonValue ack = writeConn.recv();
                        if (ack.str("type").Equals("error")) {
                            state.errors.Add(new ErrorPair(ack.str("code"), ack.str("message")));
                        } else {
                            Driver.addAck(state, "write_stream");
                        }
                        continue;
                    }
                    try {
                        Driver.driveStep(client, state, expect);
                    } catch (NanosbError e) {
                        Driver.recordError(state, e);
                    }
                }
            } finally {
                if (writeConn != null) {
                    writeConn.close();
                }
            }

            if (driveError != null) {
                return new String[]{"fail", driveError};
            }

            if (assertBlock.has("expects_unsupported") && assertBlock.boolVal("expects_unsupported")) {
                String verb = assertBlock.str("unsupported_verb");
                if (client.supports(verb)) {
                    state.unsupportedObserved = false;
                } else {
                    try {
                        client.sandbox("box").exec("echo", new List<String>());
                        state.unsupportedObserved = false;
                    } catch (NanosbError e) {
                        state.unsupportedObserved = e.errorCode.Equals("unsupported");
                    }
                }
            }

            List<String> failures = Driver.evaluateAssert(assertBlock, state);
            if (failures.Count > 0) {
                return new String[]{"fail", joinFailures(failures)};
            }
            return new String[]{"ok", ""};
        } catch (Exception e) {
            return new String[]{"fail", "driver error: " + e.Message};
        } finally {
            try {
                ph.Kill();
            } catch (Exception e) {
                // already exited
            }
            ph.WaitForExit();
            if (sock.Length > 0) {
                try {
                    File.Delete(sock);
                } catch (Exception e) {
                    Console.Error.WriteLine("cleanup: cannot remove " + sock + ": " + e.Message);
                }
            }
        }
    }

    private static String joinFailures(List<String> failures) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < failures.Count; i++) {
            if (i > 0) sb.Append("; ");
            sb.Append(failures[i]);
        }
        return sb.ToString();
    }

    public static JsonValue readScenario(String path) {
        UTF8Encoding utf8 = new UTF8Encoding();
        byte[] bytes = File.ReadAllBytes(path);
        String text = utf8.GetString(bytes, 0, bytes.Length);
        return JsonValue.parse(text);
    }

    public static String findBinary() {
        var env = Environment.GetEnvironmentVariables();
        foreach (String key in env.Keys) {
            if (key.Equals("NANOSB_CONFORMANCE_BIN")) {
                return (String) env[key];
            }
        }
        return repoRoot() + "/target/debug/nanosb-conformance";
    }

    public static String repoRoot() {
        String dir = AppContext.BaseDirectory;
        for (int i = 0; i < 12 && dir != null; i++) {
            if (Directory.Exists(Path.Combine(dir, "sdk", "conformance", "scenarios"))) {
                return dir;
            }
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) {
                break;
            }
            dir = parent.FullName;
        }
        return Directory.GetCurrentDirectory();
    }

    public static void sortStrings(List<String> arr) {
        for (int i = 0; i < arr.Count; i++) {
            for (int j = i + 1; j < arr.Count; j++) {
                if (arr[j].CompareTo(arr[i]) < 0) {
                    String tmp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = tmp;
                }
            }
        }
    }
}