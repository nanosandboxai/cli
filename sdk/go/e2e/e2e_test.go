// Real end-to-end test: drive a live microVM through the nanosandbox runtime.
//
// Opt-in — requires the nanosb-runtime helper, libkrun/gvproxy, and a cached
// image. Enable with NANOSB_E2E=1 (and optionally NANOSB_TEST_IMAGE). Mirrors
// the Rust reference smoke (crates/client/tests/live_conformance.rs).
//
//	NANOSB_E2E=1 go test ./sdk/go/e2e -run TestLiveMicroVMSmoke -v
package e2e

import (
	"os"
	"testing"
	"time"

	"github.com/nanosandboxai/nanosandbox/sdk/go/nanosandbox"
)

func image() string {
	if v := os.Getenv("NANOSB_TEST_IMAGE"); v != "" {
		return v
	}
	return "library/alpine:latest"
}

func names(list []nanosandbox.JsonValue) []string {
	out := make([]string, 0, len(list))
	for _, v := range list {
		if n, ok := v.Str("name"); ok {
			out = append(out, n)
		}
	}
	return out
}

func contains(hay []string, needle string) bool {
	for _, h := range hay {
		if h == needle {
			return true
		}
	}
	return false
}

func TestLiveMicroVMSmoke(t *testing.T) {
	if os.Getenv("NANOSB_E2E") != "1" {
		t.Skip("set NANOSB_E2E=1 to run the live microVM test")
	}

	rt, err := nanosandbox.StartRuntime(15 * time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer rt.Close()

	client, err := nanosandbox.Connect(rt.Socket)
	if err != nil {
		t.Fatal(err)
	}
	if len(client.Capabilities()) == 0 {
		t.Fatal("no capabilities advertised")
	}

	name := "sdk-e2e-go"
	spec := nanosandbox.NewSandboxBuilder(image()).WithName(name).WithResources(2, 1024).Build()
	box, err := client.Create(spec)
	if err != nil {
		t.Fatal(err)
	}

	if st, _ := box.State(); st != "running" {
		t.Fatalf("expected running, got %q", st)
	}
	info, err := client.Get(name)
	if err != nil {
		t.Fatal(err)
	}
	if n, _ := info.Str("name"); n != name {
		t.Fatalf("get name %q", n)
	}

	out, err := box.Exec("echo", []string{"hello-from-live"})
	if err != nil {
		t.Fatal(err)
	}
	if code, _ := out.Int("exit_code"); code != 0 {
		t.Fatalf("exec exit %d", code)
	}
	if so, _ := out.Str("stdout"); so != "hello-from-live\n" {
		t.Fatalf("stdout %q", so)
	}

	if err := box.FsWrite("/tmp/live-conformance", []byte("written-by-live"), false); err != nil {
		t.Fatal(err)
	}
	if s, _ := box.FsReadToString("/tmp/live-conformance"); s != "written-by-live" {
		t.Fatalf("fs_read_to_string %q", s)
	}
	if ex, _ := box.FsExists("/tmp/live-conformance"); !ex {
		t.Fatal("fs_exists false")
	}
	if err := box.FsMkdir("/tmp/live-conformance-dir", true); err != nil {
		t.Fatal(err)
	}
	stat, _ := box.FsStat("/tmp/live-conformance-dir")
	inner := stat
	if nested, ok := stat.Get("stat"); ok {
		inner = nested
	}
	if isDir, _ := inner.Bool("is_dir"); !isDir {
		t.Fatal("fs_stat is_dir false")
	}

	if lines, err := box.Logs(10); err != nil || len(lines) == 0 {
		t.Fatalf("logs: %v %v", lines, err)
	}
	if m, err := box.Metrics(); err != nil {
		t.Fatal(err)
	} else if disk, _ := m.Int("disk_used_bytes"); disk <= 0 {
		t.Fatal("metrics disk_used_bytes <= 0")
	}
	if list, err := client.List(true); err != nil || !contains(names(list), name) {
		t.Fatalf("list: %v %v", list, err)
	}

	if err := box.SecretSet("LIVE_TOKEN", "s3cr3t"); err != nil {
		t.Fatal(err)
	}
	secrets, _ := box.SecretList()
	found := false
	for _, s := range secrets {
		if k, _ := s.Str("key"); k == "LIVE_TOKEN" {
			found = true
		}
		if v, ok := s.Get("value"); ok && !v.IsNull() {
			if vs := v.AsString(); vs != "" {
				t.Fatalf("secret value must be redacted, got %q", vs)
			}
		}
	}
	if !found {
		t.Fatal("LIVE_TOKEN not listed")
	}
	if err := box.SecretRemove("LIVE_TOKEN"); err != nil {
		t.Fatal(err)
	}

	if err := box.Pause(); err != nil {
		t.Fatal(err)
	}
	if st, _ := box.State(); st != "running" {
		t.Fatalf("state after pause %q", st)
	}
	if err := box.Resume(); err != nil {
		t.Fatal(err)
	}
	after, _ := box.Exec("echo", []string{"after-resume"})
	if so, _ := after.Str("stdout"); so != "after-resume\n" {
		t.Fatal("exec after resume failed")
	}

	vol := "vol-e2e-go"
	if _, err := box.VolumeCreate(vol, rt.Dir+"/vol-data"); err != nil {
		t.Fatal(err)
	}
	if vols, _ := box.VolumeList(); !contains(names(vols), vol) {
		t.Fatal("volume not listed")
	}
	if err := box.VolumeRemove(vol); err != nil {
		t.Fatal(err)
	}

	snap, err := box.SnapshotCreate("")
	if err != nil {
		t.Fatal(err)
	}
	snapID, _ := snap.Str("id")
	if err := box.SnapshotRestore(snapID, name+"-restored"); err != nil {
		t.Fatal(err)
	}
	if err := box.SnapshotRemove(snapID); err != nil {
		t.Fatal(err)
	}
	if err := client.Sandbox(name + "-restored").Remove(true); err != nil {
		t.Fatal(err)
	}

	if err := box.Stop(true); err != nil {
		t.Fatal(err)
	}
	if err := client.Sandbox(name).Remove(true); err != nil {
		t.Fatal(err)
	}
	if list, _ := client.List(true); contains(names(list), name) {
		t.Fatal("sandbox still listed after remove")
	}
}