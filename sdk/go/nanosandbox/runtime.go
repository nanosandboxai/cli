package nanosandbox

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// FindRuntimeBin locates the nanosb-runtime helper, in order of preference:
// NANOSB_RUNTIME_BIN -> $NANOSB_HOME/bin -> PATH -> the repo target/debug build.
func FindRuntimeBin() string {
	if p := os.Getenv("NANOSB_RUNTIME_BIN"); p != "" {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	home := os.Getenv("NANOSB_HOME")
	if home == "" {
		if h, err := os.UserHomeDir(); err == nil {
			home = filepath.Join(h, ".nanosandbox")
		}
	}
	if cand := filepath.Join(home, "bin", "nanosb-runtime"); home != "" {
		if _, err := os.Stat(cand); err == nil {
			return cand
		}
	}
	if p, err := exec.LookPath("nanosb-runtime"); err == nil {
		return p
	}
	// Walk up from the working directory looking for the repo dev build.
	dir, err := os.Getwd()
	for i := 0; i < 8 && err == nil; i++ {
		cand := filepath.Join(dir, "target", "debug", "nanosb-runtime")
		if _, statErr := os.Stat(cand); statErr == nil {
			return cand
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return ""
}

// ManagedRuntime is a running nanosb-runtime helper on a private socket.
type ManagedRuntime struct {
	cmd    *exec.Cmd
	Dir    string
	Socket string
}

// StartRuntime locates the helper, serves it on a temp socket, and waits for
// the socket to appear.
func StartRuntime(wait time.Duration) (*ManagedRuntime, error) {
	bin := FindRuntimeBin()
	if bin == "" {
		return nil, fmt.Errorf(
			"nanosb-runtime not found; set NANOSB_RUNTIME_BIN or build it " +
				"(cargo build -p nanosb-cli --bin nanosb-runtime --no-default-features --features runtime-host)",
		)
	}
	dir, err := os.MkdirTemp("", "nanosb-e2e-")
	if err != nil {
		return nil, err
	}
	socket := filepath.Join(dir, "helper.sock")
	cmd := exec.Command(bin, "serve", "--socket", socket)
	if err := cmd.Start(); err != nil {
		os.RemoveAll(dir)
		return nil, err
	}
	deadline := time.Now().Add(wait)
	for {
		if _, err := os.Stat(socket); err == nil {
			return &ManagedRuntime{cmd: cmd, Dir: dir, Socket: socket}, nil
		}
		if cmd.ProcessState != nil && cmd.ProcessState.Exited() {
			os.RemoveAll(dir)
			return nil, fmt.Errorf("nanosb-runtime exited before opening its socket")
		}
		if time.Now().After(deadline) {
			_ = cmd.Process.Kill()
			os.RemoveAll(dir)
			return nil, fmt.Errorf("timed out waiting for the helper socket")
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// Close kills the helper and removes its temp directory.
func (r *ManagedRuntime) Close() {
	if r.cmd != nil && r.cmd.Process != nil {
		_ = r.cmd.Process.Kill()
		_ = r.cmd.Wait()
	}
	if r.Dir != "" {
		_ = os.RemoveAll(r.Dir)
	}
}