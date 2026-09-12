//! Server-side push notifications.
//!
//! There is no incoming-call ring to fan out anymore (CallKit/PushKit are
//! gone with the old calling product): every push here is a standard,
//! user-visible APNs alert — a match, a message, or the nightly doors-open
//! notification. [`Push`] is built once at boot, stored on
//! [`crate::state::AppState`], and [`Push::notify_alert`] loads a user's
//! `apns` subscriptions and sends to each.

pub mod apns;

use sqlx::PgPool;
use uuid::Uuid;

use crate::config::Config;

/// A single stored `apns` subscription row (one row per installation).
#[derive(Debug, sqlx::FromRow)]
struct Subscription {
    token: String,
}

#[derive(Clone)]
pub struct Push {
    apns: apns::Apns,
}

impl Push {
    /// Build from config. Disables itself when APNs credentials are unset.
    pub fn from_config(cfg: &Config) -> Self {
        Self {
            apns: apns::Apns::from_config(cfg),
        }
    }

    pub fn enabled_summary(&self) -> String {
        if self.apns.enabled() {
            "apns".to_string()
        } else {
            "none (APNs disabled — set APNS_KEY_ID/APNS_TEAM_ID/APNS_KEY_P8 to enable)".to_string()
        }
    }

    pub fn any_enabled(&self) -> bool {
        self.apns.enabled()
    }

    /// Send a standard, user-visible alert notification (banner + sound) to
    /// every `apns` subscription this user has. Never returns an error: a
    /// push failure must not fail the caller's request — every problem is
    /// logged and swallowed. `sound` is a bundled notification sound file
    /// (`None` plays the system default). `data` is merged into the push
    /// payload at the top level (alongside `aps`, never inside it) so the
    /// iOS app can route a tap by reading a custom `type` (and `matchId`)
    /// off the notification without waiting on the socket to catch up.
    #[allow(clippy::too_many_arguments)]
    pub async fn notify_alert(
        &self,
        db: &PgPool,
        user_id: Uuid,
        title: &str,
        body: &str,
        collapse_id: Option<&str>,
        sound: Option<&str>,
        ttl_secs: u32,
        data: Option<serde_json::Map<String, serde_json::Value>>,
    ) {
        let subs: Vec<Subscription> = match sqlx::query_as(
            "SELECT token FROM push_subscriptions WHERE user_id = $1 AND kind = 'apns'",
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
            tracing::info!(user = %user_id, "push: no subscriptions for alert");
            return;
        }

        for sub in subs {
            let sent = self
                .apns
                .send_alert(
                    &sub.token,
                    title,
                    body,
                    collapse_id,
                    sound,
                    ttl_secs,
                    data.as_ref(),
                )
                .await;
            if let Err(apns::ApnsError::DeadToken(reason)) = &sent {
                tracing::info!(user = %user_id, reason = %reason, "push: pruning dead APNs token");
                if let Err(e) =
                    sqlx::query("DELETE FROM push_subscriptions WHERE user_id = $1 AND token = $2")
                        .bind(user_id)
                        .bind(&sub.token)
                        .execute(db)
                        .await
                {
                    tracing::warn!(user = %user_id, error = %e, "push: failed to prune dead APNs token");
                }
            } else if let Err(apns::ApnsError::Other(error)) = &sent {
                tracing::warn!(user = %user_id, %error, "push: alert send failed");
            }
        }
    }
}
