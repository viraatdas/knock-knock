//! Time-limited TURN REST credentials (coturn `use-auth-secret` scheme).
//!
//! username = `<unix-expiry>:<user-id>`
//! password = base64( HMAC-SHA1( shared_secret, username ) )
//!
//! See <https://datatracker.ietf.org/doc/html/draft-uberti-behave-turn-rest-00>.

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use chrono::Utc;
use hmac::{Hmac, Mac};
use serde::Serialize;
use sha1::Sha1;
use uuid::Uuid;

type HmacSha1 = Hmac<Sha1>;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IceServer {
    pub urls: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credential: Option<String>,
}

/// Mint ephemeral TURN credentials valid for `ttl_secs`, returned as ICE
/// server entries ready to hand to a WebRTC `RTCPeerConnection`. A bare STUN
/// entry is prepended from the first TURN host.
pub fn ice_servers(
    shared_secret: &str,
    turn_uris: &[String],
    user_id: Uuid,
    ttl_secs: i64,
) -> Vec<IceServer> {
    let expiry = Utc::now().timestamp() + ttl_secs;
    let username = format!("{expiry}:{user_id}");

    let mut mac =
        HmacSha1::new_from_slice(shared_secret.as_bytes()).expect("HMAC accepts any key length");
    mac.update(username.as_bytes());
    let credential = B64.encode(mac.finalize().into_bytes());

    let mut servers = Vec::new();
    if let Some(stun) = stun_from_turn(turn_uris.first()) {
        servers.push(IceServer {
            urls: vec![stun],
            username: None,
            credential: None,
        });
    }
    if !turn_uris.is_empty() {
        servers.push(IceServer {
            urls: turn_uris.to_vec(),
            username: Some(username),
            credential: Some(credential),
        });
    }
    servers
}

/// Derive a `stun:host:port` URI from a `turn:host:port?...` URI.
fn stun_from_turn(turn: Option<&String>) -> Option<String> {
    let turn = turn?;
    let rest = turn.strip_prefix("turn:")?;
    let hostport = rest.split('?').next().unwrap_or(rest);
    Some(format!("stun:{hostport}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn produces_turn_and_stun() {
        let uris = vec!["turn:turn.example.com:3478?transport=udp".to_string()];
        let servers = ice_servers("secret", &uris, Uuid::nil(), 600);
        assert_eq!(servers.len(), 2);
        assert_eq!(servers[0].urls[0], "stun:turn.example.com:3478");
        assert!(servers[1].username.is_some());
        assert!(servers[1].credential.is_some());
    }

    #[test]
    fn empty_uris_yields_nothing() {
        assert!(ice_servers("secret", &[], Uuid::nil(), 600).is_empty());
    }
}
