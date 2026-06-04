//! Web Push (browser), via VAPID + RFC 8291 payload encryption.
//!
//! Uses the `web-push` crate for the ECE encryption and VAPID signing. The
//! subscription is the browser endpoint URL plus the client's `p256dh` and
//! `auth` keys captured at subscribe time.
//!
//! Disabled (no-op) unless VAPID_PRIVATE_KEY and VAPID_SUBJECT are set.

use std::sync::Arc;

use web_push::{
    ContentEncoding, SubscriptionInfo, VapidSignatureBuilder, WebPushClient, WebPushMessageBuilder,
};

use super::IncomingPush;
use crate::config::Config;

#[derive(Clone)]
pub struct WebPush(Option<Arc<Inner>>);

struct Inner {
    /// VAPID private key (base64url, the raw key bytes as in `.env.example`).
    private_key: String,
    subject: String,
    client: web_push::IsahcWebPushClient,
}

impl WebPush {
    pub fn from_config(cfg: &Config) -> Self {
        if cfg.vapid_private_key.is_empty() || cfg.vapid_subject.is_empty() {
            return WebPush(None);
        }
        let client = match web_push::IsahcWebPushClient::new() {
            Ok(c) => c,
            Err(e) => {
                tracing::error!(error = %e, "webpush: failed to build client — Web Push disabled");
                return WebPush(None);
            }
        };
        WebPush(Some(Arc::new(Inner {
            private_key: cfg.vapid_private_key.clone(),
            subject: cfg.vapid_subject.clone(),
            client,
        })))
    }

    pub fn enabled(&self) -> bool {
        self.0.is_some()
    }

    pub async fn send(
        &self,
        endpoint: &str,
        p256dh: Option<&str>,
        auth: Option<&str>,
        payload: &IncomingPush,
    ) -> Result<(), String> {
        let Some(inner) = &self.0 else {
            tracing::debug!("webpush: disabled (no credentials) — skipping");
            return Ok(());
        };
        let (Some(p256dh), Some(auth)) = (p256dh, auth) else {
            return Err("webpush: subscription missing p256dh/auth keys".to_string());
        };

        let subscription = SubscriptionInfo::new(endpoint, p256dh, auth);

        let mut sig_builder = VapidSignatureBuilder::from_base64(
            &inner.private_key,
            web_push::URL_SAFE_NO_PAD,
            &subscription,
        )
        .map_err(|e| format!("webpush vapid key invalid: {e}"))?;
        // VAPID `sub` claim: a mailto: or https: contact for the push service.
        sig_builder.add_claim("sub", inner.subject.as_str());
        let sig = sig_builder
            .build()
            .map_err(|e| format!("webpush vapid build failed: {e}"))?;

        let body = serde_json::to_vec(&payload.data_map())
            .map_err(|e| format!("webpush payload encode failed: {e}"))?;

        let mut builder = WebPushMessageBuilder::new(&subscription);
        builder.set_payload(ContentEncoding::Aes128Gcm, &body);
        builder.set_vapid_signature(sig);

        let message = builder
            .build()
            .map_err(|e| format!("webpush message build failed: {e}"))?;

        inner
            .client
            .send(message)
            .await
            .map_err(|e| format!("webpush send failed: {e}"))
    }
}
