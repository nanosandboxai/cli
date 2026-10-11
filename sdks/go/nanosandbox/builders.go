// builders.go — fluent builders for the sandbox creation spec and volume spec.
package nanosandbox

// SandboxBuilder is a fluent builder for a sandbox creation spec.
type SandboxBuilder struct {
	Image       string
	Name        string
	Cpus        int
	MemoryMb    int
	Env         []JsonPair
	Mounts      []JsonValue
	Network     JsonValue
	Workdir     string
	TimeoutSecs int
	User        string
	Home        string
	Command     string
	CommandArgs []string
	Labels      []JsonPair
	Ephemeral   bool
	Replace     bool
	Detached    bool
	Hostname    string
	SecretEnv   []JsonPair
}

// NewSandboxBuilder returns a builder for the given image.
func NewSandboxBuilder(image string) *SandboxBuilder {
	return &SandboxBuilder{
		Image:     image,
		Detached:  true,
		Network:   JsonObjectValue(),
	}
}

// WithName sets the sandbox name.
func (b *SandboxBuilder) WithName(name string) *SandboxBuilder {
	b.Name = name
	return b
}

// WithResources sets the CPU and memory allocation.
func (b *SandboxBuilder) WithResources(cpus, memoryMb int) *SandboxBuilder {
	b.Cpus = cpus
	b.MemoryMb = memoryMb
	return b
}

// WithEnv adds an environment variable.
func (b *SandboxBuilder) WithEnv(key, value string) *SandboxBuilder {
	b.Env = setPair(b.Env, key, value)
	return b
}

// WithLabel adds a label.
func (b *SandboxBuilder) WithLabel(key, value string) *SandboxBuilder {
	b.Labels = setPair(b.Labels, key, value)
	return b
}

// Mount adds a virtiofs mount.
func (b *SandboxBuilder) Mount(hostPath, guestPath string, readonly bool) *SandboxBuilder {
	m := JsonObjectValue()
	m.Set("host_path", JsonStringValue(hostPath))
	m.Set("guest_path", JsonStringValue(guestPath))
	m.Set("readonly", JsonBoolValue(readonly))
	m.Set("mount_type", JsonStringValue("virtiofs"))
	b.Mounts = append(b.Mounts, m)
	return b
}

// PublishTcp publishes a TCP port.
func (b *SandboxBuilder) PublishTcp(hostPort, guestPort int) *SandboxBuilder {
	return b.publishPort(hostPort, guestPort, "tcp")
}

// PublishUdp publishes a UDP port.
func (b *SandboxBuilder) PublishUdp(hostPort, guestPort int) *SandboxBuilder {
	return b.publishPort(hostPort, guestPort, "udp")
}

func (b *SandboxBuilder) publishPort(hostPort, guestPort int, proto string) *SandboxBuilder {
	b.Network.Set("enabled", JsonBoolValue(true))
	pub, ok := b.Network.GetArr("publish")
	if !ok {
		pub = []JsonValue{}
	}
	p := JsonObjectValue()
	p.Set("host_port", JsonIntValue(int64(hostPort)))
	p.Set("container_port", JsonIntValue(int64(guestPort)))
	p.Set("protocol", JsonStringValue(proto))
	pub = append(pub, p)
	b.Network.Set("publish", JsonValue{Kind: JsonArray, Arr: pub})
	return b
}

// Detached sets whether the helper owns the lifecycle.
func (b *SandboxBuilder) SetDetached(detached bool) *SandboxBuilder {
	b.Detached = detached
	return b
}

// Hostname overrides the guest hostname.
func (b *SandboxBuilder) SetHostname(hostname string) *SandboxBuilder {
	b.Hostname = hostname
	return b
}

// MountFile mounts a host file into the guest.
func (b *SandboxBuilder) MountFile(hostPath, guestPath string) *SandboxBuilder {
	m := JsonObjectValue()
	m.Set("host_path", JsonStringValue(hostPath))
	m.Set("guest_path", JsonStringValue(guestPath))
	m.Set("readonly", JsonBoolValue(false))
	m.Set("mount_type", JsonStringValue("virtiofs"))
	m.Set("file", JsonBoolValue(true))
	b.Mounts = append(b.Mounts, m)
	return b
}

// MountTmpfs mounts a tmpfs at the guest path.
func (b *SandboxBuilder) MountTmpfs(guestPath string) *SandboxBuilder {
	m := JsonObjectValue()
	m.Set("host_path", JsonStringValue(""))
	m.Set("guest_path", JsonStringValue(guestPath))
	m.Set("readonly", JsonBoolValue(false))
	m.Set("mount_type", JsonStringValue("tmpfs"))
	m.Set("tmpfs", JsonBoolValue(true))
	b.Mounts = append(b.Mounts, m)
	return b
}

// MountOptions sets options on the most recently added mount.
func (b *SandboxBuilder) MountOptions(options []string) *SandboxBuilder {
	if len(b.Mounts) > 0 {
		opts := JsonArrayValue()
		for _, o := range options {
			opts.Append(JsonStringValue(o))
		}
		b.Mounts[len(b.Mounts)-1].Set("options", opts)
	}
	return b
}

// MountOwner sets uid/gid on the most recently added mount.
func (b *SandboxBuilder) MountOwner(uid, gid int) *SandboxBuilder {
	if len(b.Mounts) > 0 {
		b.Mounts[len(b.Mounts)-1].Set("uid", JsonIntValue(int64(uid)))
		b.Mounts[len(b.Mounts)-1].Set("gid", JsonIntValue(int64(gid)))
	}
	return b
}

// SecretEnv maps an env key to a secret-store key.
func (b *SandboxBuilder) SetSecretEnv(key, secretKey string) *SandboxBuilder {
	b.SecretEnv = setPair(b.SecretEnv, key, secretKey)
	return b
}

// Build returns the sandbox creation spec as a JSON object.
func (b *SandboxBuilder) Build() JsonValue {
	spec := JsonObjectValue()
	spec.Set("image", JsonStringValue(b.Image))
	spec.Set("detached", JsonBoolValue(b.Detached))
	if b.Name != "" {
		spec.Set("name", JsonStringValue(b.Name))
	}
	if b.Cpus > 0 {
		spec.Set("cpus", JsonIntValue(int64(b.Cpus)))
	}
	if b.MemoryMb > 0 {
		spec.Set("memory_mb", JsonIntValue(int64(b.MemoryMb)))
	}
	if b.Workdir != "" {
		spec.Set("workdir", JsonStringValue(b.Workdir))
	}
	if b.TimeoutSecs > 0 {
		spec.Set("timeout_secs", JsonIntValue(int64(b.TimeoutSecs)))
	}
	if b.User != "" {
		spec.Set("user", JsonStringValue(b.User))
	}
	if b.Home != "" {
		spec.Set("home", JsonStringValue(b.Home))
	}
	if b.Command != "" {
		spec.Set("command", JsonStringValue(b.Command))
	}
	if b.Hostname != "" {
		spec.Set("hostname", JsonStringValue(b.Hostname))
	}
	if len(b.Env) > 0 {
		spec.Set("env", JsonValue{Kind: JsonObject, Obj: b.Env})
	}
	if len(b.Mounts) > 0 {
		spec.Set("mounts", JsonValue{Kind: JsonArray, Arr: b.Mounts})
	}
	if len(b.Network.Obj) > 0 {
		spec.Set("network", b.Network)
	}
	if len(b.CommandArgs) > 0 {
		args := JsonArrayValue()
		for _, a := range b.CommandArgs {
			args.Append(JsonStringValue(a))
		}
		spec.Set("command_args", args)
	}
	if len(b.Labels) > 0 {
		spec.Set("labels", JsonValue{Kind: JsonObject, Obj: b.Labels})
	}
	if b.Ephemeral {
		spec.Set("ephemeral", JsonBoolValue(true))
	}
	if b.Replace {
		spec.Set("replace", JsonBoolValue(true))
	}
	if len(b.SecretEnv) > 0 {
		spec.Set("secret_env", JsonValue{Kind: JsonObject, Obj: b.SecretEnv})
	}
	return spec
}

func setPair(pairs []JsonPair, key, value string) []JsonPair {
	for i := 0; i < len(pairs); i++ {
		if pairs[i].Key == key {
			pairs[i].Val = JsonStringValue(value)
			return pairs
		}
	}
	return append(pairs, JsonPair{Key: key, Val: JsonStringValue(value)})
}

// VolumeBuilder is a fluent builder for a volume creation spec.
type VolumeBuilder struct {
	Name       string
	Dir        string
	DiskImage  string
	Fstype     string
	QuotaBytes int
}

// NewVolumeBuilder returns a builder for the named volume.
func NewVolumeBuilder(name string) *VolumeBuilder {
	return &VolumeBuilder{Name: name}
}

// WithDir sets the host directory backing the volume.
func (b *VolumeBuilder) WithDir(dir string) *VolumeBuilder {
	b.Dir = dir
	return b
}

// DiskImage sets the disk-image backing.
func (b *VolumeBuilder) SetDiskImage(image string) *VolumeBuilder {
	b.DiskImage = image
	return b
}

// Fstype sets the filesystem type.
func (b *VolumeBuilder) SetFstype(fstype string) *VolumeBuilder {
	b.Fstype = fstype
	return b
}

// VolumeQuota sets the quota in bytes.
func (b *VolumeBuilder) VolumeQuota(bytes int) *VolumeBuilder {
	b.QuotaBytes = bytes
	return b
}

// Build returns the volume spec as a JSON object.
func (b *VolumeBuilder) Build() JsonValue {
	spec := JsonObjectValue()
	spec.Set("name", JsonStringValue(b.Name))
	if b.Dir != "" {
		spec.Set("dir", JsonStringValue(b.Dir))
	}
	if b.DiskImage != "" {
		spec.Set("disk_image", JsonStringValue(b.DiskImage))
	}
	if b.Fstype != "" {
		spec.Set("fstype", JsonStringValue(b.Fstype))
	}
	if b.QuotaBytes > 0 {
		spec.Set("quota_bytes", JsonIntValue(int64(b.QuotaBytes)))
	}
	return spec
}