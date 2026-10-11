// sandbox_fs.go — filesystem, storage, secrets, and snapshot verbs for
// `Sandbox`. Kept in a separate file so each source file stays focused.
package nanosandbox

import "os"

// FsRead reads bytes from a guest file.
func (b *Sandbox) FsRead(path string) ([]byte, error) {
	return b.FsReadRange(path, -1, -1)
}

// FsReadRange reads a byte range from a guest file.
func (b *Sandbox) FsReadRange(path string, offset, length int) ([]byte, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_read"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	if offset >= 0 {
		req.Set("offset", JsonIntValue(int64(offset)))
	}
	if length >= 0 {
		req.Set("length", JsonIntValue(int64(length)))
	}
	resp, err := b.Client.Call(req)
	if err != nil {
		return nil, err
	}
	b64, _ := resp.Str("data_base64")
	data, derr := Unb64(b64)
	if derr != nil {
		return nil, derr
	}
	return data, nil
}

// FsReadStream reads a guest file in chunks, delivering each to onChunk.
func (b *Sandbox) FsReadStream(path string, chunkSize int, onChunk func([]byte)) error {
	if chunkSize < 1 {
		chunkSize = 1
	}
	offset := 0
	for {
		chunk, err := b.FsReadRange(path, offset, chunkSize)
		if err != nil {
			return err
		}
		if len(chunk) == 0 {
			return nil
		}
		onChunk(chunk)
		if len(chunk) < chunkSize {
			return nil
		}
		offset += len(chunk)
	}
}

// FsWriteStream streams a file write in fs_data chunks.
func (b *Sandbox) FsWriteStream(path string, data []byte, chunkSize int) error {
	if chunkSize < 1 {
		chunkSize = 1
	}
	conn := NewConn(b.Client.Socket)
	err := conn.Open()
	if err != nil {
		return err
	}
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_write_stream"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	serr := conn.Send(req)
	if serr == nil {
		ack, aerr := conn.Recv()
		if aerr != nil {
			err = aerr
		} else if ackType(ack) == "error" {
			err = errorFrom(ack)
		} else {
			chunks := 0
			if len(data) == 0 {
				chunks = 1
			} else {
				chunks = (len(data) + chunkSize - 1) / chunkSize
			}
			for i := 0; i < chunks; i++ {
				start := i * chunkSize
				end := start + chunkSize
				if end > len(data) {
					end = len(data)
				}
				body := JsonObjectValue()
				body.Set("type", JsonStringValue("fs_data"))
				body.Set("data_base64", JsonStringValue(B64(data[start:end])))
				body.Set("eof", JsonBoolValue(i == chunks - 1))
				_, cerr := conn.Call(body)
				if cerr != nil {
					err = cerr
					break
				}
			}
		}
	} else {
		err = serr
	}
	conn.Close()
	return err
}

// FsReadToString reads a guest file as UTF-8 text.
func (b *Sandbox) FsReadToString(path string) (string, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_read_to_string"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	resp, err := b.Client.Call(req)
	if err != nil {
		return "", err
	}
	content, _ := resp.Str("content")
	return content, nil
}

// FsWrite writes bytes to a guest file.
func (b *Sandbox) FsWrite(path string, data []byte, append bool) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_write"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	req.Set("data_base64", JsonStringValue(B64(data)))
	req.Set("append", JsonBoolValue(append))
	_, err := b.Client.Call(req)
	return err
}

// FsList lists a guest directory.
func (b *Sandbox) FsList(path string) ([]JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_list"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	resp, err := b.Client.Call(req)
	if err != nil {
		return nil, err
	}
	entries, _ := resp.GetArr("entries")
	return entries, nil
}

// FsStat stats a guest path.
func (b *Sandbox) FsStat(path string) (JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_stat"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	return b.Client.Call(req)
}

// FsExists reports whether a guest path exists.
func (b *Sandbox) FsExists(path string) (bool, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_exists"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	resp, err := b.Client.Call(req)
	if err != nil {
		return false, err
	}
	exists, _ := resp.Bool("exists")
	return exists, nil
}

// FsMkdir creates a guest directory.
func (b *Sandbox) FsMkdir(path string, recursive bool) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_mkdir"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	req.Set("recursive", JsonBoolValue(recursive))
	_, err := b.Client.Call(req)
	return err
}

// FsRemove removes a guest file.
func (b *Sandbox) FsRemove(path string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_remove"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	_, err := b.Client.Call(req)
	return err
}

// FsRemoveDir removes a guest directory.
func (b *Sandbox) FsRemoveDir(path string, recursive bool) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_remove_dir"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("path", JsonStringValue(path))
	req.Set("recursive", JsonBoolValue(recursive))
	_, err := b.Client.Call(req)
	return err
}

// FsCopy copies a file inside the guest.
func (b *Sandbox) FsCopy(src, dst string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_copy"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("from", JsonStringValue(src))
	req.Set("to", JsonStringValue(dst))
	_, err := b.Client.Call(req)
	return err
}

// FsRename renames a file inside the guest.
func (b *Sandbox) FsRename(src, dst string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_rename"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("from", JsonStringValue(src))
	req.Set("to", JsonStringValue(dst))
	_, err := b.Client.Call(req)
	return err
}

// FsCopyFromHost copies a host file into the guest.
func (b *Sandbox) FsCopyFromHost(hostPath, guestPath string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_copy_from_host"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("host_path", JsonStringValue(hostPath))
	req.Set("guest_path", JsonStringValue(guestPath))
	_, err := b.Client.Call(req)
	return err
}

// FsCopyToHost copies a guest file to the host.
func (b *Sandbox) FsCopyToHost(guestPath, hostPath string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("fs_copy_to_host"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("host_path", JsonStringValue(hostPath))
	req.Set("guest_path", JsonStringValue(guestPath))
	_, err := b.Client.Call(req)
	return err
}

// VolumeCreate creates a named volume.
func (b *Sandbox) VolumeCreate(name, dir string) (JsonValue, error) {
	vol := JsonObjectValue()
	vol.Set("name", JsonStringValue(name))
	if dir != "" {
		vol.Set("dir", JsonStringValue(dir))
	}
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("volume_create"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("volume", vol)
	return b.Client.Call(req)
}

// VolumeList lists the sandbox's volumes.
func (b *Sandbox) VolumeList() ([]JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("volume_list"))
	req.Set("name", JsonStringValue(b.Name))
	resp, err := b.Client.Call(req)
	if err != nil {
		return nil, err
	}
	vols, _ := resp.GetArr("volumes")
	return vols, nil
}

// VolumeGet fetches one volume's info.
func (b *Sandbox) VolumeGet(volume string) (JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("volume_get"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("volume", JsonStringValue(volume))
	return b.Client.Call(req)
}

// VolumeRemove removes a named volume.
func (b *Sandbox) VolumeRemove(volume string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("volume_remove"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("volume", JsonStringValue(volume))
	_, err := b.Client.Call(req)
	return err
}

// VolumeFs returns the host directory backing a volume.
func (b *Sandbox) VolumeFs(name string) (string, error) {
	info, err := b.VolumeGet(name)
	if err != nil {
		return "", err
	}
	dir, ok := info.Str("dir")
	if ok && dir != "" {
		return dir, nil
	}
	home := os.Getenv("NANOSB_HOME")
	if home == "" {
		home = os.Getenv("HOME") + "/.nanosandbox"
	}
	return home + "/volumes/" + name, nil
}

// MountAdd mounts a volume into the running sandbox.
func (b *Sandbox) MountAdd(mount JsonValue) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("mount_add"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("mount", mount)
	_, err := b.Client.Call(req)
	return err
}

// SecretSet sets a named secret.
func (b *Sandbox) SecretSet(key, value string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("secret_set"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("key", JsonStringValue(key))
	req.Set("value", JsonStringValue(value))
	_, err := b.Client.Call(req)
	return err
}

// SecretList lists the sandbox's secrets (values redacted).
func (b *Sandbox) SecretList() ([]JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("secret_list"))
	req.Set("name", JsonStringValue(b.Name))
	resp, err := b.Client.Call(req)
	if err != nil {
		return nil, err
	}
	secrets, _ := resp.GetArr("secrets")
	return secrets, nil
}

// SecretRemove removes a named secret.
func (b *Sandbox) SecretRemove(key string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("secret_remove"))
	req.Set("name", JsonStringValue(b.Name))
	req.Set("key", JsonStringValue(key))
	_, err := b.Client.Call(req)
	return err
}

// SnapshotCreate creates a snapshot of the sandbox.
func (b *Sandbox) SnapshotCreate(dest string) (JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("snapshot_create"))
	req.Set("name", JsonStringValue(b.Name))
	if dest != "" {
		req.Set("dest", JsonStringValue(dest))
	}
	req.Set("include_memory", JsonBoolValue(false))
	return b.Client.Call(req)
}

// SnapshotRestore restores a sandbox from a snapshot.
func (b *Sandbox) SnapshotRestore(snapshot, name string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("snapshot_restore"))
	req.Set("snapshot", JsonStringValue(snapshot))
	req.Set("name", JsonStringValue(name))
	_, err := b.Client.Call(req)
	return err
}

// SnapshotFork forks a new sandbox from a snapshot.
func (b *Sandbox) SnapshotFork(snapshot, name string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("snapshot_fork"))
	req.Set("snapshot", JsonStringValue(snapshot))
	req.Set("name", JsonStringValue(name))
	_, err := b.Client.Call(req)
	return err
}

// SnapshotRemove removes a snapshot.
func (b *Sandbox) SnapshotRemove(snapshot string) error {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("snapshot_remove"))
	req.Set("snapshot", JsonStringValue(snapshot))
	_, err := b.Client.Call(req)
	return err
}