//! Server-side push notifications.
//!
//! There is no incoming-call ring to fan out anymore (CallKit/PushKit are
//! gone with the old calling product): every push here is a standard,
//! user-visible APNs alert — a match, a message, or the nightly doors-open
//! notification. [`Push`] is built once at boot, stored on
//! [`crate::state::AppState`], and [`Push::notify_alert`] loads a user's
//! `apns` subscriptions and sends to each. [`Push::deliver_alert`] is the
//! same fan-out with a per-token result, for the `push-test` operator command.

pub mod apns;

use std::ops::AddAssign;

use sqlx::PgPool;
use uuid::Uuid;

use crate::config::Config;

/// A single stored `apns` subscription row (one row per installation).
#[derive(Debug, sqlx::FromRow)]
struct Subscription {
    token: String,
}

/// How a fan-out to one user's subscriptions went, as counts. Summed across
/// users by the doors-open scheduler so its log line says how many pushes
/// APNs actually accepted, not how many users were looked up.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct NotifyOutcome {
    /// Tokens APNs accepted (HTTP 200).
    pub sent: usize,
    /// Tokens that failed for a transient or config reason; the row stays.
    pub failed: usize,
    /// Tokens APNs reported permanently gone; the row was deleted.
    pub pruned: usize,
}

impl AddAssign for NotifyOutcome {
    fn add_assign(&mut self, other: Self) {
        self.sent += other.sent;
        self.failed += other.failed;
        self.pruned += other.pruned;
    }
}

/// What happened to one device token during a fan-out.
pub struct TokenDelivery {
    /// The full APNs device token. Log and print it through [`mask_token`].
    pub token: String,
    pub result: Result<apns::ApnsReceipt, apns::ApnsError>,
}

/// Manual so a `{:?}` of a delivery (an `anyhow` context, a `tracing`
/// field, a stray `dbg!`) never lands the full device token in a log line.
impl std::fmt::Debug for TokenDelivery {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TokenDelivery")
            .field("token", &mask_token(&self.token))
            .field("result", &self.result)
            .finish()
    }
}

/// First 8 characters of a device token plus an ellipsis: enough to match a
/// row or a log line, not enough to push to the device.
pub fn mask_token(token: &str) -> String {
    let head: String = token.chars().take(8).collect();
    if token.chars().count() > 8 {
        format!("{head}…")
    } else {
        head
    }
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
    /// logged and swallowed, and the returned counts are informational (the
    /// match and chat callers drop them; the scheduler sums them for its
    /// log line). `sound` is a bundled notification sound file (`None` plays
    /// the system default). `data` is merged into the push payload at the
    /// top level (alongside `aps`, never inside it) so the iOS app can route
    /// a tap by reading a custom `type` (and `matchId`) off the notification
    /// without waiting on the socket to catch up.
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
    ) -> NotifyOutcome {
        let deliveries = match self
            .deliver_alert(
                db,
                user_id,
                title,
                body,
                collapse_id,
                sound,
                ttl_secs,
                data.as_ref(),
            )
            .await
        {
            Ok(deliveries) => deliveries,
            Err(e) => {
                tracing::warn!(user = %user_id, error = %e, "push: failed to load subscriptions");
                return NotifyOutcome::default();
            }
        };

        if deliveries.is_empty() {
            tracing::info!(user = %user_id, "push: no subscriptions for alert");
        }

        let mut outcome = NotifyOutcome::default();
        for delivery in &deliveries {
            match &delivery.result {
                Ok(_) => outcome.sent += 1,
                Err(apns::ApnsError::DeadToken(_)) => outcome.pruned += 1,
                Err(apns::ApnsError::Other(_)) => outcome.failed += 1,
            }
        }
        outcome
    }

    /// The fan-out behind [`Push::notify_alert`], one result per stored
    /// token. Dead tokens (APNs 410 / `BadDeviceToken`) are pruned here so
    /// both callers self-heal; other failures are logged and left alone.
    /// `Err` only when the subscription query itself fails.
    #[allow(clippy::too_many_arguments)]
    pub async fn deliver_alert(
        &self,
        db: &PgPool,
        user_id: Uuid,
        title: &str,
        body: &str,
        collapse_id: Option<&str>,
        sound: Option<&str>,
        ttl_secs: u32,
        data: Option<&serde_json::Map<String, serde_json::Value>>,
    ) -> Result<Vec<TokenDelivery>, sqlx::Error> {
        let subs: Vec<Subscription> = sqlx::query_as(
            "SELECT token FROM push_subscriptions WHERE user_id = $1 AND kind = 'apns'",
        )
        .bind(user_id)
        .fetch_all(db)
        .await?;

        let mut deliveries = Vec::with_capacity(subs.len());
        for sub in subs {
            let result = self
                .apns
                .send_alert(&sub.token, title, body, collapse_id, sound, ttl_secs, data)
                .await;
            match &result {
                Ok(_) => {}
                Err(apns::ApnsError::DeadToken(reason)) => {
                    tracing::info!(
                        user = %user_id,
                        token = %mask_token(&sub.token),
                        reason = %reason,
                        "push: pruning dead APNs token"
                    );
                    if let Err(e) = sqlx::query(
                        "DELETE FROM push_subscriptions WHERE user_id = $1 AND token = $2",
                    )
                    .bind(user_id)
                    .bind(&sub.token)
                    .execute(db)
                    .await
                    {
                        tracing::warn!(user = %user_id, error = %e, "push: failed to prune dead APNs token");
                    }
                }
                Err(apns::ApnsError::Other(error)) => {
                    tracing::warn!(
                        user = %user_id,
                        token = %mask_token(&sub.token),
                        %error,
                        "push: alert send failed"
                    );
                }
            }
            deliveries.push(TokenDelivery {
                token: sub.token,
                result,
            });
        }
        Ok(deliveries)
    }
}

#[cfg(test)]
mod tests {
    use super::{apns::ApnsError, mask_token, NotifyOutcome, TokenDelivery};

    #[test]
    fn mask_keeps_only_the_first_eight_chars() {
        assert_eq!(mask_token("0123456789abcdef0123456789abcdef"), "01234567…");
        assert_eq!(mask_token("01234567"), "01234567");
        assert_eq!(mask_token("abc"), "abc");
        assert_eq!(mask_token(""), "");
    }

    #[test]
    fn delivery_debug_masks_the_token() {
        let token = "0123456789abcdef0123456789abcdef".to_string();
        let delivery = TokenDelivery {
            token: token.clone(),
            result: Err(ApnsError::Other("boom".to_string())),
        };
        let rendered = format!("{delivery:?}");
        assert!(!rendered.contains(&token), "{rendered}");
        assert!(rendered.contains("01234567…"), "{rendered}");
    }

    #[test]
    fn outcomes_sum_field_by_field() {
        let mut total = NotifyOutcome::default();
        total += NotifyOutcome {
            sent: 1,
            failed: 0,
            pruned: 0,
        };
        total += NotifyOutcome {
            sent: 0,
            failed: 2,
            pruned: 1,
        };
        assert_eq!(
            total,
            NotifyOutcome {
                sent: 1,
                failed: 2,
                pruned: 1
            }
        );
    }
}
