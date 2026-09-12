//! POST /v1/diagnostics: unauthenticated client-side diagnostic pings (e.g.
//! "OTP send failed") so a failure that never reaches a human (a reviewer's
//! device, a user who just closes the app) still shows up in `fly logs`.
//!
//! Never stores the body: on success it emits exactly one structured
//! `tracing` line (`warn` for an `event` ending in `_failed`, `info`
//! otherwise) and returns `204`. Rate-limited 20/min per client IP, keyed off
//! `Fly-Client-IP`/`X-Forwarded-For` when present since the API runs behind
//! Fly's proxy and the TCP peer address would otherwise be Fly's edge, not
//! the caller.

use std::net::SocketAddr;

use axum::{
    extract::{ConnectInfo, State},
    http::HeaderMap,
    Json,
};
use serde::Deserialize;

use slide_core::error::{AppError, AppResult};

use crate::{otp_store, state::AppState};

const EVENT_MAX_CHARS: usize = 64;
const DETAIL_MAX_CHARS: usize = 500;
const FIELD_MAX_CHARS: usize = 64;
const RATE_LIMIT_PER_MIN: i64 = 20;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DiagnosticsBody {
    pub event: String,
    #[serde(default)]
    pub detail: Option<String>,
    pub phone_country: String,
    pub os: String,
    pub device: String,
    #[serde(default)]
    pub app: Option<String>,
}

/// Validated, borrowed form of `DiagnosticsBody` used for both the handler
/// and the unit tests below.
struct ValidatedDiagnostics<'a> {
    event: &'a str,
    detail: Option<&'a str>,
    phone_country: &'a str,
    os: &'a str,
    device: &'a str,
    app: Option<&'a str>,
}

fn validate(body: &DiagnosticsBody) -> AppResult<ValidatedDiagnostics<'_>> {
    if body.event.is_empty()
        || body.event.chars().count() > EVENT_MAX_CHARS
        || !body
            .event
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
    {
        return Err(AppError::validation(
            "event must be 1-64 chars of lowercase letters, digits, and underscores",
        ));
    }
    if let Some(detail) = &body.detail {
        if detail.chars().count() > DETAIL_MAX_CHARS {
            return Err(AppError::validation("detail is too long"));
        }
    }
    for (name, value) in [
        ("phoneCountry", body.phone_country.as_str()),
        ("os", body.os.as_str()),
        ("device", body.device.as_str()),
    ] {
        if value.is_empty() || value.chars().count() > FIELD_MAX_CHARS {
            return Err(AppError::validation(format!(
                "{name} must be 1-{FIELD_MAX_CHARS} chars"
            )));
        }
    }
    if let Some(app) = &body.app {
        if app.chars().count() > FIELD_MAX_CHARS {
            return Err(AppError::validation("app is too long"));
        }
    }
    Ok(ValidatedDiagnostics {
        event: &body.event,
        detail: body.detail.as_deref(),
        phone_country: &body.phone_country,
        os: &body.os,
        device: &body.device,
        app: body.app.as_deref(),
    })
}

/// The client's IP for rate limiting: the first hop of `Fly-Client-IP` or
/// `X-Forwarded-For` when present (the API runs behind Fly's proxy, so the
/// TCP peer is Fly's edge, not the caller), else the TCP peer address.
fn client_ip(headers: &HeaderMap, peer: SocketAddr) -> String {
    if let Some(v) = headers
        .get("fly-client-ip")
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty())
    {
        return v.to_string();
    }
    if let Some(v) = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .map(str::trim)
        .filter(|v| !v.is_empty())
    {
        return v.to_string();
    }
    peer.ip().to_string()
}

pub async fn post_diagnostics(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<DiagnosticsBody>,
) -> AppResult<axum::http::StatusCode> {
    let validated = validate(&body)?;
    let ip = client_ip(&headers, peer);

    otp_store::rate_limit(&state, &format!("rl:diag:{ip}"), RATE_LIMIT_PER_MIN, 60).await?;

    let detail = validated.detail.unwrap_or_default();
    let app = validated.app.unwrap_or_default();
    if validated.event.ends_with("_failed") {
        tracing::warn!(
            event = validated.event,
            detail,
            phone_country = validated.phone_country,
            os = validated.os,
            device = validated.device,
            app,
            ip,
            "client diagnostic"
        );
    } else {
        tracing::info!(
            event = validated.event,
            detail,
            phone_country = validated.phone_country,
            os = validated.os,
            device = validated.device,
            app,
            ip,
            "client diagnostic"
        );
    }

    Ok(axum::http::StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn body(event: &str) -> DiagnosticsBody {
        DiagnosticsBody {
            event: event.to_string(),
            detail: Some("boom".to_string()),
            phone_country: "US".to_string(),
            os: "iOS 26.6.2".to_string(),
            device: "iPhone17,2".to_string(),
            app: Some("1.1.0 (33)".to_string()),
        }
    }

    #[test]
    fn accepts_a_well_formed_body() {
        assert!(validate(&body("otp_request_failed")).is_ok());
    }

    #[test]
    fn accepts_missing_optional_fields() {
        let mut b = body("app_launched");
        b.detail = None;
        b.app = None;
        assert!(validate(&b).is_ok());
    }

    #[test]
    fn rejects_empty_event() {
        assert!(validate(&body("")).is_err());
    }

    #[test]
    fn rejects_event_over_length_limit() {
        let long = "a".repeat(EVENT_MAX_CHARS + 1);
        assert!(validate(&body(&long)).is_err());
    }

    #[test]
    fn rejects_event_with_disallowed_characters() {
        assert!(validate(&body("Otp-Failed")).is_err());
        assert!(validate(&body("otp failed")).is_err());
        assert!(validate(&body("otp_failed!")).is_err());
    }

    #[test]
    fn rejects_detail_over_length_limit() {
        let mut b = body("otp_failed");
        b.detail = Some("a".repeat(DETAIL_MAX_CHARS + 1));
        assert!(validate(&b).is_err());
    }

    #[test]
    fn rejects_missing_required_fields() {
        let mut b = body("otp_failed");
        b.os = String::new();
        assert!(validate(&b).is_err());
    }

    #[test]
    fn rejects_required_field_over_length_limit() {
        let mut b = body("otp_failed");
        b.device = "a".repeat(FIELD_MAX_CHARS + 1);
        assert!(validate(&b).is_err());
    }

    #[test]
    fn rejects_app_over_length_limit() {
        let mut b = body("otp_failed");
        b.app = Some("a".repeat(FIELD_MAX_CHARS + 1));
        assert!(validate(&b).is_err());
    }

    #[test]
    fn client_ip_prefers_fly_client_ip_then_forwarded_for_then_peer() {
        let peer: SocketAddr = "203.0.113.9:1234".parse().unwrap();

        let mut headers = HeaderMap::new();
        assert_eq!(client_ip(&headers, peer), "203.0.113.9");

        headers.insert("x-forwarded-for", "198.51.100.1, 10.0.0.1".parse().unwrap());
        assert_eq!(client_ip(&headers, peer), "198.51.100.1");

        headers.insert("fly-client-ip", "192.0.2.5".parse().unwrap());
        assert_eq!(client_ip(&headers, peer), "192.0.2.5");
    }
}
