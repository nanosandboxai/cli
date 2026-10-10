//! Minimal in-guest exec agent for nanosandbox.
//!
//! Listens on a vsock port bridged to a host unix socket by libkrun
//! (`krun_add_vsock_port2(listen=true)`). This is the dedicated host<->guest
//! channel: it does not use the network stack, so exec works even with
//! networking disabled.
//!
//! Protocol (length-prefixed JSON frames, u32 LE length prefix):
//!   host -> guest: an `Inbound` (either `ExecRequest` to start, or
//!                  `ExecControl` to drive an in-flight session)
//!   guest -> host: one `ExecEvent` per frame

use std::io::{Read, Write};
use std::sync::{Arc, Mutex};

mod proto;
mod vsock;

use nanosb_protocol::{FsEntry, FsRequest, FsResponse, FsStat};
use proto::{ExecControl, ExecEvent, ExecRequest};

fn main() {
    let port: u32 = std::env::args()
        .nth(1)
        .and_then(|p| p.parse().ok())
        .unwrap_or(1024);

    if let Err(e) = run(port) {
        diag(&format!("exec-agent: {}", e));
        std::process::exit(1);
    }
}

/// Write a diagnostic line straight to fd 2 (unbuffered, bypasses stdio).
fn diag(msg: &str) {
    let mut line = String::from(msg);
    line.push('\n');
    let bytes = line.as_bytes();
    unsafe {
        libc::write(2, bytes.as_ptr() as *const libc::c_void, bytes.len());
    }
}

fn run(port: u32) -> Result<(), String> {
    diag(&format!("exec-agent: listening on vsock port {}", port));
    // Match smolvm: the guest SERVES a vsock listener and the host connects in
    // (libkrun's `listen=true` acceptor bridges the host's unix socket to us).
    let listener = vsock::VsockListener::bind(port)?;
    loop {
        let stream = listener.accept()?;
        diag("exec-agent: host connected");
        if let Err(e) = serve(stream) {
            diag(&format!("exec-agent: session error: {}", e));
        }
    }
}

/// Shared, mutex-guarded writer so the output threads and the main loop can
/// interleave event frames safely.
#[derive(Clone)]
struct Writer {
    stream: Arc<Mutex<vsock::VsockStream>>,
}

impl Writer {
    fn send<T: serde::Serialize>(&self, value: &T) -> Result<(), String> {
        let json = serde_json::to_vec(value).map_err(|e| format!("serialize: {}", e))?;
        let len = (json.len() as u32).to_le_bytes();
        let mut s = self.stream.lock().unwrap();
        s.write_all(&len)
            .and_then(|_| s.write_all(&json))
            .and_then(|_| s.flush())
            .map_err(|e| format!("write: {}", e))
    }

    fn event(&self, event: &ExecEvent) -> Result<(), String> {
        self.send(event)
    }
}

/// Serve one host connection: handle requests and their in-flight controls.
fn serve(stream: vsock::VsockStream) -> Result<(), String> {
    let mut reader = stream.try_clone()?;
    let writer = Writer {
        stream: Arc::new(Mutex::new(stream)),
    };

    // The currently running session, if any.
    let mut active: Option<Session> = None;

    loop {
        let frame = read_frame(&mut reader)?;
        let Some(bytes) = frame else {
            if let Some(mut s) = active.take() {
                let _ = s.kill();
            }
            return Ok(());
        };

        // A frame is either a new request or a control for the active session.
        if let Ok(ctl) = serde_json::from_slice::<ExecControl>(&bytes) {
            if let Some(s) = active.as_mut() {
                if let Err(e) = s.apply(ctl) {
                    writer.event(&ExecEvent::Error { message: e })?;
                }
            }
            continue;
        }

        if let Ok(fs) = serde_json::from_slice::<FsRequest>(&bytes) {
            if let Err(e) = handle_fs(fs, &writer) {
                writer.send(&FsResponse::error(e))?;
            }
            continue;
        }

        let req: ExecRequest = match serde_json::from_slice(&bytes) {
            Ok(r) => r,
            Err(e) => {
                writer.event(&ExecEvent::Error { message: e.to_string() })?;
                continue;
            }
        };

        // The waiter thread emitted `Exit` already once the previous command
        // finished; here we only need to drop it so a new one can start.
        if let Some(s) = active.as_ref() {
            if !s.is_finished() {
                writer.event(&ExecEvent::Error {
                    message: "a command is already running".to_string(),
                })?;
                continue;
            }
            active = None;
        }

        match Session::start(req, writer.clone()) {
            Ok(s) => active = Some(s),
            Err(e) => {
                writer.event(&ExecEvent::Error { message: e })?;
                writer.event(&ExecEvent::Exit { code: 127 })?;
            }
        }
    }
}

fn handle_fs(req: FsRequest, w: &Writer) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};

    match req {
        FsRequest::FsRead { path, offset, length } => {
            let data = std::fs::read(&path).map_err(|e| format!("read {}: {}", path, e))?;
            let start = offset.unwrap_or(0) as usize;
            let end = match length {
                Some(l) => start.saturating_add(l as usize),
                None => data.len(),
            };
            let slice = data.get(start..end).unwrap_or(&[]);
            w.send(&FsResponse::FsData {
                data_base64: nanosb_protocol::base64_encode(slice),
            })
        }
        FsRequest::FsWrite { path, data_base64, append, mode } => {
            let bytes = nanosb_protocol::base64_decode(&data_base64)
                .ok_or_else(|| "invalid base64 payload".to_string())?;
            let mut opts = std::fs::OpenOptions::new();
            opts.write(true).create(true);
            if append {
                opts.append(true);
            } else {
                opts.truncate(true);
            }
            let mut file = opts.open(&path).map_err(|e| format!("write {}: {}", path, e))?;
            file.write_all(&bytes).map_err(|e| format!("write {}: {}", path, e))?;
            if let Some(m) = mode {
                let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(m));
            }
            w.send(&FsResponse::Ok)
        }
        FsRequest::FsList { path } => {
            let mut entries = Vec::new();
            let dir = std::fs::read_dir(&path).map_err(|e| format!("list {}: {}", path, e))?;
            for entry in dir {
                let entry = entry.map_err(|e| format!("list {}: {}", path, e))?;
                let p = entry.path();
                let meta = entry.metadata().map_err(|e| format!("stat {}: {}", p.display(), e))?;
                let sym = std::fs::symlink_metadata(&p).ok();
                entries.push(FsEntry {
                    name: entry.file_name().to_string_lossy().to_string(),
                    path: p.to_string_lossy().to_string(),
                    is_dir: meta.is_dir(),
                    is_symlink: sym.map(|m| m.file_type().is_symlink()).unwrap_or(false),
                    size: meta.len(),
                    mode: Some(meta.permissions().mode()),
                });
            }
            entries.sort_by(|a, b| a.name.cmp(&b.name));
            w.send(&FsResponse::FsEntries { entries })
        }
        FsRequest::FsStat { path } => {
            let meta = std::fs::symlink_metadata(&path).map_err(|e| format!("stat {}: {}", path, e))?;
            let modified_ms = meta
                .modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as u64);
            w.send(&FsResponse::FsStat {
                stat: FsStat {
                    path,
                    is_dir: meta.is_dir(),
                    is_symlink: meta.file_type().is_symlink(),
                    size: meta.len(),
                    mode: Some(meta.permissions().mode()),
                    modified_ms,
                },
            })
        }
        FsRequest::FsExists { path } => w.send(&FsResponse::FsExists {
            exists: Path::new(&path).exists(),
        }),
        FsRequest::FsMkdir { path, recursive, mode } => {
            if recursive {
                std::fs::create_dir_all(&path).map_err(|e| format!("mkdir {}: {}", path, e))?;
            } else {
                std::fs::create_dir(&path).map_err(|e| format!("mkdir {}: {}", path, e))?;
            }
            if let Some(m) = mode {
                let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(m));
            }
            w.send(&FsResponse::Ok)
        }
        FsRequest::FsRemove { path } => {
            std::fs::remove_file(&path).map_err(|e| format!("remove {}: {}", path, e))?;
            w.send(&FsResponse::Ok)
        }
        FsRequest::FsRemoveDir { path, recursive } => {
            if recursive {
                std::fs::remove_dir_all(&path).map_err(|e| format!("rmdir {}: {}", path, e))?;
            } else {
                std::fs::remove_dir(&path).map_err(|e| format!("rmdir {}: {}", path, e))?;
            }
            w.send(&FsResponse::Ok)
        }
        FsRequest::FsCopy { from, to } => {
            copy_path(std::path::PathBuf::from(&from), std::path::PathBuf::from(&to))?;
            w.send(&FsResponse::Ok)
        }
        FsRequest::FsRename { from, to } => {
            std::fs::rename(&from, &to).map_err(|e| format!("rename {}: {}", from, e))?;
            w.send(&FsResponse::Ok)
        }
    }
}

fn copy_path(from: std::path::PathBuf, to: std::path::PathBuf) -> Result<(), String> {
    let meta = std::fs::symlink_metadata(&from).map_err(|e| format!("copy {}: {}", from.display(), e))?;
    if meta.is_dir() {
        std::fs::create_dir_all(&to).map_err(|e| format!("copy dir {}: {}", to.display(), e))?;
        for entry in std::fs::read_dir(&from).map_err(|e| format!("copy {}: {}", from.display(), e))? {
            let entry = entry.map_err(|e| format!("copy {}: {}", from.display(), e))?;
            copy_path(entry.path(), to.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        std::fs::copy(&from, &to)
            .map(|_| ())
            .map_err(|e| format!("copy {}: {}", from.display(), e))
    }
}

/// A running (or just-finished) command.
struct Session {
    pid: u32,
    stdin: Option<std::process::ChildStdin>,
    pty_master: Option<std::os::fd::RawFd>,
    done: Arc<std::sync::atomic::AtomicBool>,
}

impl Session {
    fn start(req: ExecRequest, writer: Writer) -> Result<Self, String> {
        use std::os::fd::FromRawFd;
        use std::os::unix::process::CommandExt;
        use std::process::{Command, Stdio};

        let (program, args) = if req.shell {
            (
                "/bin/sh".to_string(),
                vec!["-c".to_string(), req.command.clone()],
            )
        } else {
            (req.command.clone(), req.args.clone())
        };

        // PTY mode: one master fd carries merged stdout/stderr and accepts
        // stdin/resize; the child gets the slave as its controlling terminal.
        let mut pty_master: Option<std::os::fd::RawFd> = None;
        let mut pty_slave: Option<std::os::fd::RawFd> = None;
        let mut cmd = Command::new(&program);
        cmd.args(&args);

        if req.tty {
            let (master, slave) = openpty(req.cols.max(1), req.rows.max(1))?;
            // Child's stdio all point at the slave; `pre_exec` makes it the
            // controlling terminal via fd 0 (already the slave at that point).
            unsafe {
                cmd.stdin(Stdio::from_raw_fd(libc::dup(slave)));
                cmd.stdout(Stdio::from_raw_fd(libc::dup(slave)));
                cmd.stderr(Stdio::from_raw_fd(libc::dup(slave)));
                cmd.pre_exec(move || {
                    if libc::setsid() < 0 {
                        return Err(std::io::Error::last_os_error());
                    }
                    if libc::ioctl(0, libc::TIOCSCTTY, 0) < 0 {
                        return Err(std::io::Error::last_os_error());
                    }
                    Ok(())
                });
                // Parent keeps only the master; close its slave copy after spawn.
            }
            pty_master = Some(master);
            pty_slave = Some(slave);
        } else {
            cmd.stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());
        }

        if let Some(cwd) = &req.cwd {
            cmd.current_dir(cwd);
        }
        for (k, v) in &req.env {
            cmd.env(k, v);
        }

        let mut child = cmd
            .spawn()
            .map_err(|e| format!("spawn {}: {}", program, e))?;

        // Close the parent's slave copy now that the child owns its own dups.
        if let Some(slave) = pty_slave {
            unsafe { libc::close(slave) };
        }

        writer.event(&ExecEvent::Started { pid: child.id() })?;

        let pid = child.id();

        if let Some(master) = pty_master {
            // Stream the PTY master as stdout (stderr is merged by the kernel).
            let w = writer.clone();
            let mfd = master;
            std::thread::spawn(move || {
                let mut f = unsafe { <std::fs::File as std::os::fd::FromRawFd>::from_raw_fd(mfd) };
                let mut buf = [0u8; 4096];
                while let Ok(n) = f.read(&mut buf) {
                    if n == 0 {
                        break;
                    }
                    let _ = w.event(&ExecEvent::Stdout {
                        data: String::from_utf8_lossy(&buf[..n]).to_string(),
                    });
                }
            });

            let done = Arc::new(std::sync::atomic::AtomicBool::new(false));
            {
                let done = done.clone();
                let w = writer.clone();
                let timeout = req.timeout_secs;
                std::thread::spawn(move || {
                    if timeout > 0 {
                        let deadline =
                            std::time::Instant::now() + std::time::Duration::from_secs(timeout);
                        loop {
                            if done.load(std::sync::atomic::Ordering::Relaxed) {
                                return;
                            }
                            if std::time::Instant::now() >= deadline {
                                unsafe { libc::kill(pid as i32, libc::SIGKILL) };
                                break;
                            }
                            std::thread::sleep(std::time::Duration::from_millis(100));
                        }
                    }
                    let code = match child.wait() {
                        Ok(st) => st.code().unwrap_or(-1),
                        Err(_) => -1,
                    };
                    let _ = w.event(&ExecEvent::Exit { code });
                    done.store(true, std::sync::atomic::Ordering::Relaxed);
                });
            }

            return Ok(Session {
                pid,
                stdin: None,
                pty_master: Some(master),
                done,
            });
        }

        let stdin = child.stdin.take();
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        if let Some(mut s) = stdout {
            let w = writer.clone();
            std::thread::spawn(move || {
                let mut buf = [0u8; 4096];
                while let Ok(n) = s.read(&mut buf) {
                    if n == 0 {
                        break;
                    }
                    let _ = w.event(&ExecEvent::Stdout {
                        data: String::from_utf8_lossy(&buf[..n]).to_string(),
                    });
                }
            });
        }
        if let Some(mut s) = stderr {
            let w = writer.clone();
            std::thread::spawn(move || {
                let mut buf = [0u8; 4096];
                while let Ok(n) = s.read(&mut buf) {
                    if n == 0 {
                        break;
                    }
                    let _ = w.event(&ExecEvent::Stderr {
                        data: String::from_utf8_lossy(&buf[..n]).to_string(),
                    });
                }
            });
        }

        // Waiter thread: owns the child, emits Exit when it finishes. Signals and
        // kills are delivered by PID so this thread stays the sole reaper. The
        // session `active` flag is cleared via the shared `done` handle.
        let done = Arc::new(std::sync::atomic::AtomicBool::new(false));
        {
            let done = done.clone();
            let w = writer.clone();
            let timeout = req.timeout_secs;
            std::thread::spawn(move || {
                if timeout > 0 {
                    let deadline =
                        std::time::Instant::now() + std::time::Duration::from_secs(timeout);
                    loop {
                        if done.load(std::sync::atomic::Ordering::Relaxed) {
                            return;
                        }
                        if std::time::Instant::now() >= deadline {
                            unsafe {
                                libc::kill(pid as i32, libc::SIGKILL);
                            }
                            break;
                        }
                        std::thread::sleep(std::time::Duration::from_millis(100));
                    }
                }
                let code = match child.wait() {
                    Ok(st) => st.code().unwrap_or(-1),
                    Err(_) => -1,
                };
                let _ = w.event(&ExecEvent::Exit { code });
                done.store(true, std::sync::atomic::Ordering::Relaxed);
            });
        }

        Ok(Session {
            pid,
            stdin,
            pty_master: None,
            done,
        })
    }

    fn apply(&mut self, ctl: ExecControl) -> Result<(), String> {
        match ctl {
            ExecControl::Stdin { data } => {
                if let Some(mfd) = self.pty_master {
                    let bytes = data.as_bytes();
                    let mut off = 0;
                    while off < bytes.len() {
                        let n = unsafe {
                            libc::write(
                                mfd,
                                bytes[off..].as_ptr() as *const libc::c_void,
                                bytes.len() - off,
                            )
                        };
                        if n <= 0 {
                            break;
                        }
                        off += n as usize;
                    }
                } else if let Some(si) = self.stdin.as_mut() {
                    si.write_all(data.as_bytes())
                        .map_err(|e| format!("stdin write: {}", e))?;
                    si.flush().ok();
                }
            }
            ExecControl::StdinClose => {
                self.stdin = None;
            }
            ExecControl::Signal { signal } => {
                unsafe { libc::kill(self.pid as i32, signal) };
            }
            ExecControl::Kill => {
                unsafe { libc::kill(self.pid as i32, libc::SIGKILL) };
            }
            ExecControl::Resize { cols, rows } => {
                if let Some(mfd) = self.pty_master {
                    let ws = libc::winsize {
                        ws_row: rows,
                        ws_col: cols,
                        ws_xpixel: 0,
                        ws_ypixel: 0,
                    };
                    unsafe {
                        libc::ioctl(mfd, libc::TIOCSWINSZ, &ws);
                    }
                }
            }
        }
        Ok(())
    }

    /// True once the waiter thread has reported the process exit.
    fn is_finished(&self) -> bool {
        self.done.load(std::sync::atomic::Ordering::Relaxed)
    }

    fn kill(&mut self) -> Result<(), String> {
        unsafe { libc::kill(self.pid as i32, libc::SIGKILL) };
        Ok(())
    }
}

/// Allocate a pseudo-terminal pair, sized `cols` x `rows`.
fn openpty(cols: u16, rows: u16) -> Result<(std::os::fd::RawFd, std::os::fd::RawFd), String> {
    let mut master: libc::c_int = -1;
    let mut slave: libc::c_int = -1;
    let mut ws = libc::winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let ret = unsafe {
        libc::openpty(
            &mut master,
            &mut slave,
            std::ptr::null_mut(),
            std::ptr::null(),
            &mut ws,
        )
    };
    if ret < 0 {
        return Err(format!("openpty: {}", std::io::Error::last_os_error()));
    }
    Ok((master, slave))
}

/// Read one length-prefixed frame; `None` on clean EOF.
fn read_frame(reader: &mut vsock::VsockStream) -> Result<Option<Vec<u8>>, String> {
    let mut len_buf = [0u8; 4];
    match reader.read_exact(&mut len_buf) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(format!("read len: {}", e)),
    }
    let len = u32::from_le_bytes(len_buf) as usize;
    if len > 64 * 1024 * 1024 {
        return Err(format!("frame too large: {}", len));
    }
    let mut buf = vec![0u8; len];
    reader
        .read_exact(&mut buf)
        .map_err(|e| format!("read body: {}", e))?;
    Ok(Some(buf))
}
