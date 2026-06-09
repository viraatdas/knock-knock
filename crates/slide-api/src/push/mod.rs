//! Server-side push notifications: ring a callee whose app is closed or
//! backgrounded when the realtime WebSocket can't deliver (0 live sockets).
//!
//! Three providers, each its own module and each a NO-OP that logs and returns
//! `Ok` when its credentials are unset, so the build and runtime work with no
//! configuration:
//!
//!   - [`apns`]    — iOS VoIP push (APNs HTTP/2, ES256 JWT).
//!   - [`fcm`]     — Android data message (FCM HTTP v1, OAuth2 service account).
//!   - [`webpush`] — browser Web Push (VAPID, RFC 8291 ECE).
//!
//! [`Push`] is built once at boot, stored on [`crate::state::AppState`], and
//! summarizes which providers are live. [`Push::notify_incoming`] loads a
//! user's `push_subscriptions` and fans the payload out to the matching sender.

pub mod apns;
pub mod fcm;
pub mod webpush;

use serde::Serialize;
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use crate::config::Config;

/// A single stored subscription row (one row per device/browser).
#[derive(Debug, sqlx::FromRow)]
struct Subscription {
    kind: String,
    token: String,
    p256dh: Option<String>,
    auth: Option<String>,
}

/// The payload that rings a callee. Serialized into each provider's transport.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IncomingPush {
    /// "incoming_call" — and we add `knock: true` for escalated knocks.
    #[serde(rename = "type")]
    pub kind: String,
    pub call_id: Option<Uuid>,
    pub call_type: Option<String>,
    pub from_user_id: Uuid,
    pub from_name: String,
    /// Whether accepting this call should publish camera immediately.
    pub video_enabled: bool,
    /// "call" for normal calls, "knock" for call-style knock invitations.
    pub ring_style: String,
    /// True when this push is an offline knock escalated to a ringable call,
    /// so clients can label it differently.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub knock: bool,
}

impl IncomingPush {
    /// Flatten to a JSON object for transports that carry an arbitrary map
    /// (FCM data, Web Push body). String-valued so FCM `data` is happy.
    fn data_map(&self) -> Value {
        let mut map = serde_json::Map::new();
        map.insert("type".into(), Value::String(self.kind.clone()));
        if let Some(id) = self.call_id {
            map.insert("callId".into(), Value::String(id.to_string()));
        }
        if let Some(ct) = &self.call_type {
            map.insert("callType".into(), Value::String(ct.clone()));
        }
        map.insert(
            "fromUserId".into(),
            Value::String(self.from_user_id.to_string()),
        );
        map.insert("fromName".into(), Value::String(self.from_name.clone()));
        map.insert(
            "videoEnabled".into(),
            Value::String(self.video_enabled.to_string()),
        );
        map.insert("ringStyle".into(), Value::String(self.ring_style.clone()));
        if self.knock {
            map.insert("knock".into(), Value::String("true".into()));
        }
        Value::Object(map)
    }
}

/// Holds the three (possibly disabled) senders.
#[derive(Clone)]
pub struct Push {
    apns: apns::Apns,
    fcm: fcm::Fcm,
    webpush: webpush::WebPush,
}

impl Push {
    /// Build from config. Each sender self-disables when its env is unset.
    pub fn from_config(cfg: &Config) -> Self {
        Self {
            apns: apns::Apns::from_config(cfg),
            fcm: fcm::Fcm::from_config(cfg),
            webpush: webpush::WebPush::from_config(cfg),
        }
    }

    /// Human-readable list of enabled providers for the startup log.
    pub fn enabled_summary(&self) -> String {
        let mut on = Vec::new();
        if self.apns.enabled() {
            on.push("apns");
        }
        if self.fcm.enabled() {
            on.push("fcm");
        }
        if self.webpush.enabled() {
            on.push("webpush");
        }
        if on.is_empty() {
            "none (all push providers disabled — set credentials to enable)".to_string()
        } else {
            on.join(", ")
        }
    }

    /// Load a user's subscriptions and dispatch `payload` to each matching
    /// sender. Never returns an error: a push failure must not fail the call —
    /// every problem is logged and swallowed.
    pub async fn notify_incoming(&self, db: &PgPool, user_id: Uuid, payload: &IncomingPush) {
        let subs: Vec<Subscription> = match sqlx::query_as(
            "SELECT kind, token, p256dh, auth FROM push_subscriptions WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_all(db)
        .await
        {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!(user = %user_id, error = %e, "push: failed to load subscriptions");
                return;
            }
        };

        if subs.is_empty() {
            tracing::info!(user = %user_id, "push: no subscriptions for offline user");
            return;
        }

        for sub in subs {
            let result = match sub.kind.as_str() {
                "apns_voip" if payload.kind == "incoming_call" => {
                    self.apns.send(&sub.token, payload).await
                }
                "apns_voip" => {
                    tracing::debug!(
                        kind = %payload.kind,
                        "push: skipping APNs VoIP for non-call notification"
                    );
                    Ok(())
                }
                "fcm" => self.fcm.send(&sub.token, payload).await,
                "webpush" => {
                    self.webpush
                        .send(
                            &sub.token,
                            sub.p256dh.as_deref(),
                            sub.auth.as_deref(),
                            payload,
                        )
                        .await
                }
                other => {
                    tracing::warn!(kind = %other, "push: unknown subscription kind, skipping");
                    Ok(())
                }
            };
            if let Err(e) = result {
                tracing::warn!(user = %user_id, kind = %sub.kind, error = %e, "push: send failed");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use uuid::Uuid;

    use super::IncomingPush;

    #[test]
    fn call_style_knock_push_contains_call_contract_fields() {
        let call_id = Uuid::parse_str("11111111-1111-4111-8111-111111111111").unwrap();
        let from_user_id = Uuid::parse_str("22222222-2222-4222-8222-222222222222").unwrap();
        let payload = IncomingPush {
            kind: "incoming_call".to_string(),
            call_id: Some(call_id),
            call_type: Some("one_to_one".to_string()),
            from_user_id,
            from_name: "Taariv".to_string(),
            video_enabled: false,
            ring_style: "knock".to_string(),
            knock: true,
        };

        assert_eq!(
            payload.data_map(),
            json!({
                "type": "incoming_call",
                "callId": call_id.to_string(),
                "callType": "one_to_one",
                "fromUserId": from_user_id.to_string(),
                "fromName": "Taariv",
                "videoEnabled": "false",
                "ringStyle": "knock",
                "knock": "true",
            })
        );
    }

    #[test]
    fn normal_call_push_does_not_set_knock_flag() {
        let from_user_id = Uuid::parse_str("22222222-2222-4222-8222-222222222222").unwrap();
        let payload = IncomingPush {
            kind: "incoming_call".to_string(),
            call_id: None,
            call_type: None,
            from_user_id,
            from_name: "Nikita".to_string(),
            video_enabled: true,
            ring_style: "call".to_string(),
            knock: false,
        };

        let data = payload.data_map();
        assert_eq!(data["type"], "incoming_call");
        assert_eq!(data["videoEnabled"], "true");
        assert_eq!(data["ringStyle"], "call");
        assert!(data.get("knock").is_none());
    }

    #[test]
    fn call_ended_push_keeps_terminal_event_type() {
        let call_id = Uuid::parse_str("11111111-1111-4111-8111-111111111111").unwrap();
        let from_user_id = Uuid::parse_str("22222222-2222-4222-8222-222222222222").unwrap();
        let payload = IncomingPush {
            kind: "call_ended".to_string(),
            call_id: Some(call_id),
            call_type: None,
            from_user_id,
            from_name: "Slide".to_string(),
            video_enabled: true,
            ring_style: "call".to_string(),
            knock: false,
        };

        let data = payload.data_map();
        assert_eq!(data["type"], "call_ended");
        assert_eq!(data["callId"], call_id.to_string());
        assert!(data.get("knock").is_none());
    }
}
