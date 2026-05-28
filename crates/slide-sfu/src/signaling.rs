//! The JSON signaling protocol spoken over the SFU media WebSocket.
//!
//! The client connects to `sfuUrl` (`/ws?room=<id>&token=<joinToken>`) and
//! exchanges these messages to negotiate WebRTC with the SFU. The SFU is the
//! single peer each client talks to; it forwards media between clients.

use serde::{Deserialize, Serialize};

/// Client → SFU.
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    /// Client's SDP offer (it publishes its tracks and subscribes to others).
    Offer { sdp: String },
    /// Answer to an SFU-initiated renegotiation offer.
    Answer { sdp: String },
    /// Trickled ICE candidate.
    Ice {
        candidate: String,
        #[serde(default)]
        sdp_mid: Option<String>,
        #[serde(default)]
        sdp_mline_index: Option<u16>,
    },
    /// Keepalive.
    Ping,
}

/// SFU → client.
#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
    /// SFU's SDP answer to the client's offer.
    Answer {
        sdp: String,
    },
    /// SFU-initiated offer (when new remote tracks must be added → renegotiation).
    Offer {
        sdp: String,
    },
    /// Trickled ICE candidate from the SFU.
    Ice {
        candidate: String,
        sdp_mid: Option<String>,
        sdp_mline_index: Option<u16>,
    },
    /// A new participant published media.
    PeerJoined {
        user_id: String,
    },
    /// A participant left; their tracks are gone.
    PeerLeft {
        user_id: String,
    },
    Pong,
    Error {
        message: String,
    },
}
