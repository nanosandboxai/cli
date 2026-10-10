//! Filesystem frame types for the guest exec channel.
//!
//! These ride the same length-prefixed JSON transport as exec, so `fs` works
//! even with networking disabled. Both the in-guest exec-agent and the host
//! (`runtime::exec`) use this single definition.

use serde::{Deserialize, Serialize};

use crate::types::{FsEntry, FsStat};

/// Guest-side filesystem operation. Tagged by `type` on the wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum FsRequest {
    FsRead {
        path: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        offset: Option<u64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        length: Option<u64>,
    },
    FsWrite {
        path: String,
        data_base64: String,
        #[serde(default)]
        append: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mode: Option<u32>,
    },
    FsList {
        path: String,
    },
    FsStat {
        path: String,
    },
    FsExists {
        path: String,
    },
    FsMkdir {
        path: String,
        #[serde(default)]
        recursive: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mode: Option<u32>,
    },
    FsRemove {
        path: String,
    },
    FsRemoveDir {
        path: String,
        #[serde(default)]
        recursive: bool,
    },
    FsCopy {
        from: String,
        to: String,
    },
    FsRename {
        from: String,
        to: String,
    },
}

/// Guest-side filesystem result. Tagged by `type` on the wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum FsResponse {
    FsData { data_base64: String },
    FsEntries { entries: Vec<FsEntry> },
    FsStat { stat: FsStat },
    FsExists { exists: bool },
    Ok,
    Error { message: String },
}

impl FsResponse {
    pub fn error(message: impl Into<String>) -> Self {
        FsResponse::Error {
            message: message.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fs_request_roundtrips() {
        let req = FsRequest::FsRead {
            path: "/etc/hosts".into(),
            offset: Some(1),
            length: Some(4),
        };
        let s = serde_json::to_string(&req).unwrap();
        assert!(s.contains("\"type\":\"fs_read\""));
        assert_eq!(serde_json::from_str::<FsRequest>(&s).unwrap(), req);
    }

    #[test]
    fn fs_request_does_not_parse_as_exec() {
        let s = serde_json::to_string(&FsRequest::FsList { path: "/".into() }).unwrap();
        // ExecRequest requires `command`.
        assert!(serde_json::from_str::<serde_json::Value>(&s)
            .unwrap()
            .get("command")
            .is_none());
    }

    #[test]
    fn fs_response_roundtrips() {
        let resp = FsResponse::FsExists { exists: true };
        let s = serde_json::to_string(&resp).unwrap();
        assert_eq!(serde_json::from_str::<FsResponse>(&s).unwrap(), resp);
    }
}
