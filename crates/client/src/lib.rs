//! # nanosb-client
//!
//! `SandboxClient` — the reference protocol client for the nanosandbox helper.
//! Thin, synchronous, and backend-abstracted: [`Backend::Local`] dials a Unix
//! socket; [`Backend::Cloud`] is a stub (D6).
//!
//! ```no_run
//! use nanosb_client::{SandboxBuilder, SandboxClient};
//!
//! let client = SandboxClient::local().unwrap();
//! let sandbox = client
//!     .create_with(SandboxBuilder::new("alpine:latest").name("demo"))
//!     .unwrap();
//! let out = sandbox.exec("echo", &["hi"]).unwrap();
//! assert_eq!(out.stdout, "hi\n");
//! ```

#![forbid(unsafe_code)]
#![allow(missing_docs)]
#![warn(clippy::all)]

pub mod builder;
pub mod client;
pub mod connection;
pub mod error;
pub mod testserver;

pub use builder::SandboxBuilder;
pub use client::{home, Backend, Sandbox, SandboxClient};
pub use connection::{default_helper_socket, sandbox_control_socket, sandbox_dir};
pub use error::{Error, Result};

pub use nanosb_protocol as protocol;
