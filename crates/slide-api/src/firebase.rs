//! Firebase Phone Auth ID-token verification.
//!
//! The iOS app performs the phone-number + SMS-code flow with the Firebase SDK
//! (Google sends the SMS on their carrier-approved infrastructure, so no
//! toll-free/10DLC registration is needed). The app then sends us the resulting
//! Firebase ID token; we verify it here and mint our own Slide session tokens.
//!
//! A Firebase ID token is an RS256 JWT signed by Google. We verify it against
//! Google's rotating public certs, checking signature, expiry, audience
//! (= Firebase project id), and issuer (= securetoken.google.com/<project>).
//! Verification rules: https://firebase.google.com/docs/auth/admin/verify-id-tokens

use std::sync::Arc;
use std::time::{Duration, Instant};

use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use slide_core::error::{AppError, AppResult};
use tokio::sync::RwLock;

const CERTS_URL: &str =
    "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com";

/// Claims we care about from a Firebase ID token.
#[derive(Debug, Deserialize)]
pub struct FirebaseClaims {
    /// Firebase user id (uid). Retained for completeness / future use.
    #[allow(dead_code)]
    pub sub: String,
    #[serde(default)]
    pub phone_number: Option<String>,
}

/// Verifies Firebase ID tokens, caching Google's public certs (kid -> PEM).
#[derive(Clone)]
pub struct FirebaseVerifier {
    project_id: String,
    http: reqwest::Client,
    cache: Arc<RwLock<CertCache>>,
}

#[derive(Default)]
struct CertCache {
    /// kid -> x509 PEM string.
    certs: std::collections::HashMap<String, String>,
    fetched_at: Option<Instant>,
}

impl FirebaseVerifier {
    pub fn new(project_id: String) -> Self {
        Self {
            project_id,
            http: reqwest::Client::new(),
            cache: Arc::new(RwLock::new(CertCache::default())),
        }
    }

    /// True when a project id is configured (Firebase auth enabled).
    pub fn is_configured(&self) -> bool {
        !self.project_id.is_empty()
    }

    async fn cert_for_kid(&self, kid: &str) -> AppResult<String> {
        // Fast path: cached and fresh (< 1h).
        {
            let c = self.cache.read().await;
            if let Some(at) = c.fetched_at {
                if at.elapsed() < Duration::from_secs(3600) {
                    if let Some(pem) = c.certs.get(kid) {
                        return Ok(pem.clone());
                    }
                }
            }
        }
        // Refresh from Google.
        let resp = self
            .http
            .get(CERTS_URL)
            .send()
            .await
            .map_err(|e| AppError::unavailable(format!("firebase certs fetch: {e}")))?;
        let map: std::collections::HashMap<String, String> = resp
            .json()
            .await
            .map_err(|e| AppError::unavailable(format!("firebase certs parse: {e}")))?;
        let mut c = self.cache.write().await;
        c.certs = map;
        c.fetched_at = Some(Instant::now());
        c.certs
            .get(kid)
            .cloned()
            .ok_or_else(|| AppError::Unauthorized)
    }

    /// Verify a Firebase ID token; returns its claims on success.
    pub async fn verify(&self, id_token: &str) -> AppResult<FirebaseClaims> {
        if !self.is_configured() {
            return Err(AppError::unavailable("firebase auth not configured"));
        }
        let header = decode_header(id_token).map_err(|_| AppError::Unauthorized)?;
        let kid = header.kid.ok_or(AppError::Unauthorized)?;
        let pem = self.cert_for_kid(&kid).await?;
        let key = DecodingKey::from_rsa_pem(pem.as_bytes())
            .map_err(|e| AppError::unavailable(format!("firebase key: {e}")))?;

        let mut v = Validation::new(Algorithm::RS256);
        v.set_audience(&[&self.project_id]);
        v.set_issuer(&[&format!("https://securetoken.google.com/{}", self.project_id)]);
        v.leeway = 30;

        let data = decode::<FirebaseClaims>(id_token, &key, &v).map_err(|_| AppError::Unauthorized)?;
        Ok(data.claims)
    }
}
