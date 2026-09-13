//! APNs alert push (iOS).
//!
//! HTTP/2 to `api.push.apple.com` (or the sandbox host), authenticated with a
//! provider JWT signed ES256 using the APNs `.p8` key. Every push here is a
//! standard, user-visible alert (banner + sound) — there is no VoIP/PushKit
//! path anymore (no CallKit anywhere in this app).
//!
//! APNs speaks HTTP/2 only. reqwest negotiates h2 over TLS via ALPN, but only
//! when its `http2` cargo feature is on (workspace `Cargo.toml`); without it
//! the client offers `http/1.1` alone, Apple closes the connection, and every
//! send fails with "error sending request". The `http2_*` builder calls below
//! only compile with that feature, so dropping it breaks the build instead of
//! silently breaking every push in production.
//!
//! Disabled unless APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8 and APNS_TOPIC are
//! all set; attempted sends then return a logged delivery error.

use std::sync::{Arc, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::Serialize;
use serde_json::json;

use crate::config::Config;

/// Refresh the provider JWT well before APNs' 60-min limit.
const TOKEN_REFRESH_SECS: u64 = 45 * 60;

/// HTTP/2 PING cadence on the pooled APNs connection. Apple recommends keeping
/// provider connections open between pushes (reconnecting per push is the slow
/// path and gets rate-limited); pings keep the idle connection from being
/// dropped by a NAT or by APNs between the nightly 7 PM burst and the next
/// match/message push, and let hyper notice a dead one before a send hangs.
///
/// The pings only matter if the pool keeps the idle connection at all:
/// reqwest evicts idle connections after 90 s by default, which would make
/// them moot. The client builder sets `pool_idle_timeout(None)` so the one
/// APNs connection stays pooled for as long as the pings say it is alive.
const H2_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(60);
const H2_KEEP_ALIVE_TIMEOUT: Duration = Duration::from_secs(20);

/// What APNs answered for one accepted push.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApnsReceipt {
    /// Always 200 today; kept so operator tooling prints what Apple sent.
    pub status: u16,
    /// Apple's `apns-id` for the notification, the handle to quote to Apple
    /// when a push was accepted but never showed up on the device.
    pub apns_id: Option<String>,
}

/// Why an APNs send failed. `DeadToken` means APNs told us the device token is
/// permanently gone (HTTP 410 "Unregistered", or 400 with reason
/// "BadDeviceToken") — callers should prune the subscription row. Everything
/// else (5xx, network, auth) is `Other` and must NOT trigger pruning.
#[derive(Debug)]
pub enum ApnsError {
    DeadToken(String),
    Other(String),
}

impl std::fmt::Display for ApnsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApnsError::DeadToken(msg) | ApnsError::Other(msg) => f.write_str(msg),
        }
    }
}

/// Wrap a reqwest transport failure (connect, TLS, timeout, h2) as
/// [`ApnsError::Other`]. reqwest's error `Display` appends the request URL,
/// and the APNs URL ends in the full device token (`/3/device/<token>`), so
/// the URL is stripped first: a full token must never reach the logs or the
/// `push-test` output (callers only ever print it through `mask_token`). The
/// underlying cause chain is kept, because "error sending request" on its
/// own says nothing about why.
fn transport_error(e: reqwest::Error) -> ApnsError {
    let e = e.without_url();
    let mut msg = format!("apns alert request failed: {e}");
    let mut source = std::error::Error::source(&e);
    while let Some(cause) = source {
        msg.push_str(": ");
        msg.push_str(&cause.to_string());
        source = cause.source();
    }
    ApnsError::Other(msg)
}

/// Classify an APNs error response: 410 always means the token is gone;
/// 400 only when the body's reason is "BadDeviceToken".
fn classify_failure(status: reqwest::StatusCode, body: &str) -> ApnsError {
    let msg = format!("apns status {status}: {body}");
    let reason = serde_json::from_str::<serde_json::Value>(body)
        .ok()
        .and_then(|value| value.get("reason")?.as_str().map(str::to_owned));
    if status == reqwest::StatusCode::GONE
        || (status == reqwest::StatusCode::BAD_REQUEST
            && reason.as_deref() == Some("BadDeviceToken"))
    {
        ApnsError::DeadToken(msg)
    } else {
        ApnsError::Other(msg)
    }
}

/// Build the APNs alert payload: `aps` plus any custom top-level fields
/// (never nested inside `aps`) so the client can read a `type` (and
/// `matchId`, for message/match pushes) off the notification without a
/// separate socket round trip.
fn build_payload(
    title: &str,
    body: &str,
    sound: Option<&str>,
    data: Option<&serde_json::Map<String, serde_json::Value>>,
) -> serde_json::Value {
    let mut payload = serde_json::Map::new();
    payload.insert(
        "aps".to_string(),
        json!({
            "alert": { "title": title, "body": body },
            "sound": sound.unwrap_or("default"),
        }),
    );
    if let Some(data) = data {
        for (key, value) in data {
            payload.insert(key.clone(), value.clone());
        }
    }
    serde_json::Value::Object(payload)
}

#[derive(Clone)]
pub struct Apns(Option<Arc<Inner>>);

struct Inner {
    key_id: String,
    team_id: String,
    /// Bare bundle-id topic (e.g. "app.exla.slide") for standard alert pushes.
    topic: String,
    host: &'static str,
    encoding_key: EncodingKey,
    http: reqwest::Client,
    /// Cached provider token: (jwt, issued_at_epoch_secs).
    cached: RwLock<Option<(String, u64)>>,
}

#[derive(Serialize)]
struct Claims {
    iss: String,
    iat: u64,
}

impl Apns {
    pub fn from_config(cfg: &Config) -> Self {
        if cfg.apns_key_id.is_empty()
            || cfg.apns_team_id.is_empty()
            || cfg.apns_key_p8.is_empty()
            || cfg.apns_topic.is_empty()
        {
            return Apns(None);
        }

        // APNS_KEY_P8 may be the PEM contents or a path to the .p8 file.
        let pem = load_p8(&cfg.apns_key_p8);
        let encoding_key = match EncodingKey::from_ec_pem(pem.as_bytes()) {
            Ok(k) => k,
            Err(e) => {
                tracing::error!(error = %e, "apns: invalid .p8 key — APNs disabled");
                return Apns(None);
            }
        };

        // HTTP/2 is required by APNs. reqwest negotiates h2 over TLS (ALPN,
        // offering h2 then http/1.1) as long as its `http2` feature is on; do
        // not force prior-knowledge h2 here, ALPN is what Apple documents.
        // The http2_* calls are feature-gated, which is the compile-time check
        // that the feature did not get dropped (see the module docs).
        //
        // The connection is meant to live between pushes: `pool_idle_timeout
        // (None)` stops reqwest from evicting it after its default 90 s idle,
        // and the keep-alive pings (see `H2_KEEP_ALIVE_INTERVAL`) then keep
        // it open and replace a dead one instead of hanging the next send.
        let http = match reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(10))
            .pool_idle_timeout(None)
            .http2_keep_alive_interval(H2_KEEP_ALIVE_INTERVAL)
            .http2_keep_alive_timeout(H2_KEEP_ALIVE_TIMEOUT)
            .http2_keep_alive_while_idle(true)
            .build()
        {
            Ok(c) => c,
            Err(e) => {
                tracing::error!(error = %e, "apns: failed to build http client — APNs disabled");
                return Apns(None);
            }
        };

        let host = if cfg.apns_env == "sandbox" {
            "https://api.sandbox.push.apple.com"
        } else {
            "https://api.push.apple.com"
        };

        Apns(Some(Arc::new(Inner {
            key_id: cfg.apns_key_id.clone(),
            team_id: cfg.apns_team_id.clone(),
            topic: cfg.apns_topic.clone(),
            host,
            encoding_key,
            http,
            cached: RwLock::new(None),
        })))
    }

    pub fn enabled(&self) -> bool {
        self.0.is_some()
    }

    /// Send a standard, user-visible alert push (banner + sound). `sound` is a
    /// bundled sound file name (e.g. "knock.caf"); `None` plays the system
    /// default. `data` is merged into the payload at the top level, alongside
    /// `aps` (never inside it), so the iOS app can read a custom `type` (and
    /// `matchId`, for message/match pushes) off the notification's
    /// `userInfo` to route a tap without waiting on a socket. `Ok` carries
    /// Apple's status and `apns-id`; `Err` says whether the token is dead.
    #[allow(clippy::too_many_arguments)]
    pub async fn send_alert(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        collapse_id: Option<&str>,
        sound: Option<&str>,
        ttl_secs: u32,
        data: Option<&serde_json::Map<String, serde_json::Value>>,
    ) -> Result<ApnsReceipt, ApnsError> {
        let Some(inner) = &self.0 else {
            return Err(ApnsError::Other(
                "apns disabled: missing or invalid credentials".to_string(),
            ));
        };

        let jwt = inner.provider_token().map_err(ApnsError::Other)?;

        let payload = build_payload(title, body, sound, data);

        let url = format!("{}/3/device/{}", inner.host, device_token);
        let mut req = inner
            .http
            .post(&url)
            .bearer_auth(&jwt)
            .header("apns-topic", &inner.topic)
            .header("apns-push-type", "alert")
            .header("apns-priority", "10")
            .header(
                "apns-expiration",
                unix_now().saturating_add(u64::from(ttl_secs)).to_string(),
            );
        if let Some(cid) = collapse_id {
            req = req.header("apns-collapse-id", cid);
        }
        let resp = req.json(&payload).send().await.map_err(transport_error)?;

        let status = resp.status();
        if status.is_success() {
            let apns_id = resp
                .headers()
                .get("apns-id")
                .and_then(|v| v.to_str().ok())
                .map(str::to_owned);
            Ok(ApnsReceipt {
                status: status.as_u16(),
                apns_id,
            })
        } else {
            let txt = resp.text().await.unwrap_or_default();
            Err(classify_failure(status, &txt))
        }
    }
}

impl Inner {
    /// Return a cached provider JWT, minting a fresh one when stale.
    fn provider_token(&self) -> Result<String, String> {
        let now = unix_now();
        if let Ok(guard) = self.cached.read() {
            if let Some((tok, iat)) = guard.as_ref() {
                if now.saturating_sub(*iat) < TOKEN_REFRESH_SECS {
                    return Ok(tok.clone());
                }
            }
        }

        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let claims = Claims {
            iss: self.team_id.clone(),
            iat: now,
        };
        let tok = jsonwebtoken::encode(&header, &claims, &self.encoding_key)
            .map_err(|e| format!("apns jwt sign failed: {e}"))?;

        if let Ok(mut guard) = self.cached.write() {
            *guard = Some((tok.clone(), now));
        }
        Ok(tok)
    }
}

/// Accept the PEM inline or as a filesystem path.
fn load_p8(value: &str) -> String {
    if value.contains("BEGIN") {
        value.to_string()
    } else {
        match std::fs::read_to_string(value) {
            Ok(contents) => contents,
            Err(_) => value.to_string(),
        }
    }
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use reqwest::StatusCode;

    use super::{build_payload, classify_failure, transport_error, ApnsError};

    /// reqwest's error `Display` appends the request URL, and the APNs URL
    /// ends in the full device token. Drive a real send at a loopback port
    /// nothing listens on (no network needed, fails on connect) so the error
    /// is the same kind `send_alert` sees, then check the token is gone.
    #[tokio::test]
    async fn transport_errors_never_carry_the_device_token() {
        let token = "0123456789abcdef".repeat(4);
        assert_eq!(token.len(), 64);
        let url = format!("http://127.0.0.1:1/3/device/{token}");
        let client = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap();
        let err = client
            .post(&url)
            .send()
            .await
            .expect_err("nothing listens on loopback port 1");
        // The raw reqwest error is exactly what used to leak; proves the
        // assertion below is not vacuous.
        assert!(
            err.to_string().contains(&token),
            "reqwest no longer prints the url: {err}"
        );

        let msg = transport_error(err).to_string();
        assert!(
            msg.starts_with("apns alert request failed: "),
            "unexpected prefix: {msg}"
        );
        assert!(!msg.contains(&token), "device token leaked: {msg}");
        assert!(!msg.contains("127.0.0.1"), "request url leaked: {msg}");
    }

    #[test]
    fn payload_without_data_has_only_aps() {
        let payload = build_payload("Knock Knock", "Doors are open.", Some("knock.caf"), None);
        assert_eq!(
            payload,
            serde_json::json!({
                "aps": { "alert": { "title": "Knock Knock", "body": "Doors are open." }, "sound": "knock.caf" }
            })
        );
    }

    #[test]
    fn payload_merges_custom_data_alongside_aps() {
        let mut data = serde_json::Map::new();
        data.insert("type".to_string(), serde_json::json!("message"));
        data.insert("matchId".to_string(), serde_json::json!("match-123"));

        let payload = build_payload("Sam", "Hey there", None, Some(&data));

        assert_eq!(
            payload,
            serde_json::json!({
                "aps": { "alert": { "title": "Sam", "body": "Hey there" }, "sound": "default" },
                "type": "message",
                "matchId": "match-123",
            })
        );
        // Custom fields sit at the top level, never nested inside "aps".
        assert!(payload.get("aps").unwrap().get("type").is_none());
    }

    #[test]
    fn only_permanent_apns_errors_are_dead_tokens() {
        assert!(matches!(
            classify_failure(StatusCode::GONE, r#"{"reason":"Unregistered"}"#),
            ApnsError::DeadToken(_)
        ));
        assert!(matches!(
            classify_failure(StatusCode::BAD_REQUEST, r#"{"reason":"BadDeviceToken"}"#),
            ApnsError::DeadToken(_)
        ));
        assert!(matches!(
            classify_failure(StatusCode::BAD_REQUEST, r#"{"reason":"BadTopic"}"#),
            ApnsError::Other(_)
        ));
        assert!(matches!(
            classify_failure(StatusCode::INTERNAL_SERVER_ERROR, ""),
            ApnsError::Other(_)
        ));
    }
}
