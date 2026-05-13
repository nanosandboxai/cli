//! Event system for the TUI.

use std::sync::Arc;
use std::time::Duration;

use ratatui::crossterm::event::{self, Event as CrosstermEvent};
#[cfg(target_os = "windows")]
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use tokio::sync::{mpsc, Mutex};

use sandbox::Sandbox;

/// Events that the TUI application can handle.
pub enum AppEvent {
    /// A terminal input event (key press, mouse, resize, etc.).
    Terminal(CrosstermEvent),
    /// Periodic tick for UI refresh.
    Tick,
    /// Sandbox creation started for a panel: index and status message.
    SandboxCreating {
        /// Panel index.
        panel_idx: usize,
        /// Human-readable status message.
        message: String,
    },
    /// Sandbox successfully created and started.
    SandboxReady {
        /// Panel index.
        panel_idx: usize,
        /// Shared sandbox handle.
        sandbox: Arc<Mutex<Sandbox>>,
        /// Short sandbox identifier for display.
        short_id: String,
        /// Project mount transferred from the sandbox (if any).
        project_mount: Option<sandbox::ProjectMount>,
    },
    /// Sandbox creation or startup failed.
    SandboxFailed {
        /// Panel index.
        panel_idx: usize,
        /// Error description.
        error: String,
    },
    /// SSH terminal connected and shell is active.
    SshConnected {
        /// Panel index.
        panel_idx: usize,
        /// Handle for sending keystrokes and resize events.
        handle: super::terminal::SshTerminalHandle,
    },
    /// Data received from SSH channel for a panel's terminal.
    TerminalData {
        /// Panel index.
        panel_idx: usize,
        /// Raw bytes from the SSH channel.
        data: Vec<u8>,
    },
    /// SSH connection failed or disconnected.
    SshDisconnected {
        /// Panel index.
        panel_idx: usize,
        /// Error description (None for clean disconnect).
        error: Option<String>,
    },
    /// Open a TUI tool (suspend terminal, launch tool, resume on exit).
    OpenTuiTool {
        /// Binary name of the tool to launch.
        binary: String,
        /// Path to the clone directory to open.
        path: std::path::PathBuf,
    },
    /// File upload to sandbox started (for immediate feedback).
    UploadStarted {
        /// Panel index.
        panel_idx: usize,
        /// Filename being uploaded.
        filename: String,
    },
    /// File upload to sandbox completed successfully.
    UploadComplete {
        /// Panel index.
        panel_idx: usize,
        /// Original filename.
        filename: String,
        /// Remote path inside the VM.
        remote_path: String,
        /// Bytes transferred.
        size: u64,
    },
    /// File upload to sandbox failed.
    UploadFailed {
        /// Panel index.
        panel_idx: usize,
        /// Error description.
        error: String,
    },
}

/// Spawn a background task that reads terminal events and forwards them to the channel.
pub fn spawn_terminal_event_reader(tx: mpsc::UnboundedSender<AppEvent>) {
    tokio::spawn(async move {
        #[cfg(target_os = "windows")]
        let mut consecutive_read_errors: u32 = 0;

        loop {
            // Blocking read wrapped in spawn_blocking to avoid blocking the async runtime.
            //
            // On Windows we use poll()+read() instead of a bare blocking read().
            // crossterm's event::read() performs a save→modify→read→restore cycle
            // on the console input mode; the "restore" briefly re-enables
            // QUICK_EDIT_MODE which can freeze the TUI if the user clicks during
            // that window.  By polling with a short timeout we keep the window
            // small and can re-apply our console mode fix frequently.
            //
            // We also drain *all* available events in one spawn_blocking call so
            // that rapid-fire key events (Windows pastes individual characters
            // when bracketed paste is unsupported) are batched together.
            let events = tokio::task::spawn_blocking(|| {
                let mut batch: Vec<CrosstermEvent> = Vec::new();

                // Wait for the first event (up to 100ms on Windows, blocking on others).
                #[cfg(target_os = "windows")]
                let has_first = match event::poll(Duration::from_millis(100)) {
                    Ok(true) => match event::read() {
                        Ok(evt) => { batch.push(evt); true }
                        Err(_) => false,
                    },
                    Ok(false) => false, // timeout, no event
                    Err(_) => false,
                };
                #[cfg(not(target_os = "windows"))]
                let has_first = match event::read() {
                    Ok(evt) => { batch.push(evt); true }
                    Err(_) => false,
                };

                // Drain any immediately-available follow-up events (non-blocking).
                // This batches rapid-fire key events from Windows paste.
                if has_first {
                    while let Ok(true) = event::poll(Duration::ZERO) {
                        match event::read() {
                            Ok(evt) => batch.push(evt),
                            Err(_) => break,
                        }
                    }
                }

                #[cfg(target_os = "windows")]
                super::run::fix_windows_console_mode();

                (has_first, batch)
            })
            .await;

            match events {
                Ok((true, batch)) => {
                    #[cfg(target_os = "windows")]
                    {
                        consecutive_read_errors = 0;
                    }

                    // On Windows, coalesce sequential printable-char Press
                    // events into synthetic Paste events so injected clipboard
                    // text is forwarded in bulk through bracketed paste.
                    #[cfg(target_os = "windows")]
                    let batch = coalesce_char_events(batch);

                    for evt in batch {
                        if tx.send(AppEvent::Terminal(evt)).is_err() {
                            return; // receiver dropped
                        }
                    }
                }
                Ok((false, _)) => {
                    // poll() timeout (Windows) — not an error, loop again.
                    #[cfg(target_os = "windows")]
                    continue;
                    #[cfg(not(target_os = "windows"))]
                    break;
                }
                _ => {
                    #[cfg(target_os = "windows")]
                    {
                        consecutive_read_errors = consecutive_read_errors.saturating_add(1);
                        super::run::fix_windows_console_mode();
                        if consecutive_read_errors <= 50 {
                            tokio::time::sleep(Duration::from_millis(20)).await;
                            continue;
                        }
                    }

                    // Error reading event or task panicked; stop.
                    break;
                }
            }
        }
    });
}

#[cfg(target_os = "windows")]
fn coalesce_char_events(events: Vec<CrosstermEvent>) -> Vec<CrosstermEvent> {
    use ratatui::crossterm::event::KeyEventKind;

    if events.len() <= 3 {
        return events;
    }

    let mut result: Vec<CrosstermEvent> = Vec::with_capacity(events.len());
    let mut char_buf = String::new();

    for evt in events {
        match &evt {
            CrosstermEvent::Key(key)
                if key.kind == KeyEventKind::Press
                    && key.modifiers.is_empty()
                    && matches!(key.code, KeyCode::Char(_)) =>
            {
                if let KeyCode::Char(c) = key.code {
                    char_buf.push(c);
                }
            }
            _ => {
                if !char_buf.is_empty() {
                    if char_buf.len() >= 2 {
                        result.push(CrosstermEvent::Paste(std::mem::take(&mut char_buf)));
                    } else {
                        let c = char_buf.chars().next().unwrap();
                        char_buf.clear();
                        result.push(CrosstermEvent::Key(KeyEvent::new(
                            KeyCode::Char(c),
                            KeyModifiers::NONE,
                        )));
                    }
                }
                result.push(evt);
            }
        }
    }

    if !char_buf.is_empty() {
        if char_buf.len() >= 2 {
            result.push(CrosstermEvent::Paste(char_buf));
        } else {
            let c = char_buf.chars().next().unwrap();
            result.push(CrosstermEvent::Key(KeyEvent::new(
                KeyCode::Char(c),
                KeyModifiers::NONE,
            )));
        }
    }

    result
}

