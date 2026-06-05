//! LiveKit access-token minting.
//!
//! A LiveKit token is a plain HS256 JWT signed with the server's `api_secret`,
//! carrying `iss = api_key` and a custom `video` grant (the room the client may
//! join + what it may do there). The LiveKit server validates it on connect, so
//! no server-to-server RPC is needed — minting here in the control plane is the
//! whole integration. See https://docs.livekit.io/home/get-started/authentication/
//!
//! We replace the legacy custom-SFU join token with this: the client connects to
//! `livekit_url` with the LiveKit SDK using the returned token; the room name is
//! the call id so both participants land in the same room.

use chrono::Utc;
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::Serialize;

/// The `video` grant — camelCase to match LiveKit's wire format.
#[derive(Serialize)]
struct VideoGrant {
    room: String,
    #[serde(rename = "roomJoin")]
    room_join: bool,
    #[serde(rename = "canPublish")]
    can_publish: bool,
    #[serde(rename = "canSubscribe")]
    can_subscribe: bool,
    #[serde(rename = "canPublishData")]
    can_publish_data: bool,
}

#[derive(Serialize)]
struct Claims {
    iss: String,
    sub: String,
    nbf: i64,
    exp: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
    video: VideoGrant,
}

/// Mint a LiveKit access token admitting `identity` (display `name`) to `room`
/// as a normal publishing+subscribing participant, valid for `ttl_secs`.
pub fn mint_token(
    api_key: &str,
    api_secret: &str,
    identity: &str,
    name: Option<&str>,
    room: &str,
    ttl_secs: i64,
) -> jsonwebtoken::errors::Result<String> {
    let now = Utc::now().timestamp();
    let claims = Claims {
        iss: api_key.to_string(),
        sub: identity.to_string(),
        nbf: now - 5,
        exp: now + ttl_secs,
        name: name.map(str::to_string),
        video: VideoGrant {
            room: room.to_string(),
            room_join: true,
            can_publish: true,
            can_subscribe: true,
            can_publish_data: true,
        },
    };
    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(api_secret.as_bytes()),
    )
}
