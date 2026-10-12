// Builders.cs — fluent builders for sandbox creation specs and volumes.

using System.Collections.Generic;
using System;

/// Fluent builder for a sandbox creation spec.
public class SandboxBuilder {
    private String image;
    private String name;
    private int cpus;
    private int memoryMb;
    private Dictionary<String, String> env;
    private List<JsonValue> mounts;
    private JsonValue network;
    private String workdir;
    private int timeoutSecs;
    private String user;
    private String home;
    private String command;
    private List<String> commandArgs;
    private Dictionary<String, String> labels;
    private bool ephemeral;
    private bool replace;
    private String hostname;

    public SandboxBuilder(String image) {
        this.image = image;
        this.cpus = -1;
        this.memoryMb = -1;
        this.timeoutSecs = -1;
        this.env = new Dictionary<String, String>();
        this.mounts = new List<JsonValue>();
        this.network = JsonValue.makeObject();
        this.commandArgs = new List<String>();
        this.labels = new Dictionary<String, String>();
    }

    public SandboxBuilder withName(String name) {
        this.name = name;
        return this;
    }

    public SandboxBuilder withResources(int cpus, int memoryMb) {
        this.cpus = cpus;
        this.memoryMb = memoryMb;
        return this;
    }

    public SandboxBuilder withEnv(String key, String value) {
        this.env[key] = value;
        return this;
    }

    public SandboxBuilder withMount(JsonValue mount) {
        this.mounts.Add(mount);
        return this;
    }

    public SandboxBuilder withNetwork(JsonValue network) {
        this.network = network;
        return this;
    }

    public SandboxBuilder publishTcp(int hostPort, int containerPort) {
        if (!network.has("enabled")) {
            network.put("enabled", JsonValue.of(true));
        }
        JsonValue publish = network.has("publish") ? network.get("publish") : JsonValue.makeArray();
        if (!network.has("publish")) {
            network.put("publish", publish);
        }
        JsonValue entry = JsonValue.makeObject();
        entry.put("host_port", JsonValue.of((long) hostPort));
        entry.put("container_port", JsonValue.of((long) containerPort));
        entry.put("protocol", JsonValue.of("tcp"));
        publish.add(entry);
        return this;
    }

    public SandboxBuilder withWorkdir(String workdir) {
        this.workdir = workdir;
        return this;
    }

    public SandboxBuilder withTimeout(int timeoutSecs) {
        this.timeoutSecs = timeoutSecs;
        return this;
    }

    public SandboxBuilder withUser(String user) {
        this.user = user;
        return this;
    }

    public SandboxBuilder withHome(String home) {
        this.home = home;
        return this;
    }

    public SandboxBuilder withCommand(String command, List<String> args) {
        this.command = command;
        this.commandArgs = args;
        return this;
    }

    public SandboxBuilder withLabel(String key, String value) {
        this.labels[key] = value;
        return this;
    }

    public SandboxBuilder withEphemeral(bool ephemeral) {
        this.ephemeral = ephemeral;
        return this;
    }

    public SandboxBuilder withReplace(bool replace) {
        this.replace = replace;
        return this;
    }

    public SandboxBuilder withHostname(String hostname) {
        this.hostname = hostname;
        return this;
    }

    public JsonValue build() {
        JsonValue spec = JsonValue.makeObject();
        spec.put("image", JsonValue.of(image));
        if (name != null) {
            spec.put("name", JsonValue.of(name));
        }
        if (cpus > 0) {
            spec.put("cpus", JsonValue.of((long) cpus));
        }
        if (memoryMb > 0) {
            spec.put("memory_mb", JsonValue.of((long) memoryMb));
        }
        if (env.Count > 0) {
            JsonValue envObj = JsonValue.makeObject();
            foreach (String key in env.Keys) {
                envObj.put(key, JsonValue.of(env[key]));
            }
            spec.put("env", envObj);
        }
        if (mounts.Count > 0) {
            JsonValue mountsArr = JsonValue.makeArray();
            for (int i = 0; i < mounts.Count; i++) {
                mountsArr.add(mounts[i]);
            }
            spec.put("mounts", mountsArr);
        }
        if (network.has("enabled") || network.has("publish")) {
            spec.put("network", network);
        }
        if (workdir != null) {
            spec.put("workdir", JsonValue.of(workdir));
        }
        if (timeoutSecs > 0) {
            spec.put("timeout_secs", JsonValue.of((long) timeoutSecs));
        }
        if (user != null) {
            spec.put("user", JsonValue.of(user));
        }
        if (home != null) {
            spec.put("home", JsonValue.of(home));
        }
        if (command != null) {
            spec.put("command", JsonValue.of(command));
            JsonValue argsArr = JsonValue.makeArray();
            for (int i = 0; i < commandArgs.Count; i++) {
                argsArr.add(JsonValue.of(commandArgs[i]));
            }
            spec.put("command_args", argsArr);
        }
        if (labels.Count > 0) {
            JsonValue labelsObj = JsonValue.makeObject();
            foreach (String key in labels.Keys) {
                labelsObj.put(key, JsonValue.of(labels[key]));
            }
            spec.put("labels", labelsObj);
        }
        if (ephemeral) {
            spec.put("ephemeral", JsonValue.of(true));
        }
        if (replace) {
            spec.put("replace", JsonValue.of(true));
        }
        if (hostname != null) {
            spec.put("hostname", JsonValue.of(hostname));
        }
        return spec;
    }
}

/// Fluent builder for a volume spec.
public class VolumeBuilder {
    private String name;
    private String dir;

    public VolumeBuilder(String name) {
        this.name = name;
    }

    public VolumeBuilder withDir(String dir) {
        this.dir = dir;
        return this;
    }

    public JsonValue build() {
        JsonValue vol = JsonValue.makeObject();
        vol.put("name", JsonValue.of(name));
        if (dir != null) {
            vol.put("dir", JsonValue.of(dir));
        }
        return vol;
    }
}