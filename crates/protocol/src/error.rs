//! Protocol error type and stable error codes.

use serde::{Deserialize, Serialize};
use std::fmt;

/// Stable, language-neutral error codes. SDKs may branch on these.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    /// The request could not be parsed / is malformed.
    BadRequest,
    /// The protocol version is incompatible.
    IncompatibleVersion,
    /// The named sandbox does not exist.
    NotFound,
    /// The sandbox exists but is not in a state to serve the request.
    InvalidState,
    /// The requested verb is not supported by this helper build.
    Unsupported,
    /// Authentication / authorisation failure.
    Unauthorized,
    /// A timeout elapsed.
    Timeout,
    /// The underlying transport (socket) failed.
    Transport,
    /// An I/O or filesystem error occurred.
    Io,
    /// Anything else; see `message`.
    Internal,
}

impl ErrorCode {
    /// Stable wire string for this code.
    pub fn as_str(self) -> &'static str {
        match self {
            ErrorCode::BadRequest => "bad_request",
            ErrorCode::IncompatibleVersion => "incompatible_version",
            ErrorCode::NotFound => "not_found",
            ErrorCode::InvalidState => "invalid_state",
            ErrorCode::Unsupported => "unsupported",
            ErrorCode::Unauthorized => "unauthorized",
            ErrorCode::Timeout => "timeout",
            ErrorCode::Transport => "transport",
            ErrorCode::Io => "io",
            ErrorCode::Internal => "internal",
        }
    }
}

/// A protocol-level error: a stable `code` plus a human-readable `message`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProtocolError {
    pub code: ErrorCode,
    pub message: String,
}

impl ProtocolError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::BadRequest, message)
    }

    pub fn not_found(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::NotFound, message)
    }

    pub fn invalid_state(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InvalidState, message)
    }

    pub fn unsupported(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Unsupported, message)
    }

    pub fn io(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Io, message)
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Internal, message)
    }
}

impl fmt::Display for ProtocolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code.as_str(), self.message)
    }
}

impl std::error::Error for ProtocolError {}
