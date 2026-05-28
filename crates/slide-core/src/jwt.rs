//! JWT minting/verification for stateless access tokens and SFU join tokens.
//!
//! - **Access token**: short-lived (~15m), HS256, carries `userId` only. Used as
//!   the bearer for the REST API and the app-signaling WebSocket.
//! - **Join token**: short-lived (~5m), HS256 under a separate SFU secret,
//!   room-scoped. Handed to the client by the control plane and validated by the
//!   SFU node before allowing media negotiation.
//!
//! Refresh tokens are *not* JWTs — they are opaque random strings stored hashed
//! in Postgres so they can be rotated and revoked. See `slide-api`.

use chrono::Utc;
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

const ACCESS_AUD: &str = "slide:access";
const JOIN_AUD: &str = "slide:sfu";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessClaims {
    /// Subject — the user id.
    pub sub: Uuid,
    pub aud: String,
    pub iat: i64,
    pub exp: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoinClaims {
    /// Subject — the user id.
    pub sub: Uuid,
    pub aud: String,
    pub room_id: String,
    pub sfu_node_id: String,
    pub call_id: Uuid,
    pub iat: i64,
    pub exp: i64,
}

/// Holds an HS256 key pair for one token family.
#[derive(Clone)]
pub struct TokenSigner {
    encoding: EncodingKey,
    decoding: DecodingKey,
}

impl TokenSigner {
    pub fn new(secret: &str) -> Self {
        Self {
            encoding: EncodingKey::from_secret(secret.as_bytes()),
            decoding: DecodingKey::from_secret(secret.as_bytes()),
        }
    }

    /// Mint an access token valid for `ttl_secs`.
    pub fn sign_access(
        &self,
        user_id: Uuid,
        ttl_secs: i64,
    ) -> jsonwebtoken::errors::Result<String> {
        let now = Utc::now().timestamp();
        let claims = AccessClaims {
            sub: user_id,
            aud: ACCESS_AUD.to_string(),
            iat: now,
            exp: now + ttl_secs,
        };
        encode(&Header::new(Algorithm::HS256), &claims, &self.encoding)
    }

    pub fn verify_access(&self, token: &str) -> jsonwebtoken::errors::Result<AccessClaims> {
        let mut v = Validation::new(Algorithm::HS256);
        v.set_audience(&[ACCESS_AUD]);
        // Strict expiry: no grace window. Access tokens are short-lived and the
        // client silently refreshes, so we don't want expired tokens to linger.
        v.leeway = 0;
        Ok(decode::<AccessClaims>(token, &self.decoding, &v)?.claims)
    }

    /// Mint a room-scoped SFU join token.
    pub fn sign_join(
        &self,
        user_id: Uuid,
        call_id: Uuid,
        room_id: &str,
        sfu_node_id: &str,
        ttl_secs: i64,
    ) -> jsonwebtoken::errors::Result<String> {
        let now = Utc::now().timestamp();
        let claims = JoinClaims {
            sub: user_id,
            aud: JOIN_AUD.to_string(),
            room_id: room_id.to_string(),
            sfu_node_id: sfu_node_id.to_string(),
            call_id,
            iat: now,
            exp: now + ttl_secs,
        };
        encode(&Header::new(Algorithm::HS256), &claims, &self.encoding)
    }

    pub fn verify_join(&self, token: &str) -> jsonwebtoken::errors::Result<JoinClaims> {
        let mut v = Validation::new(Algorithm::HS256);
        v.set_audience(&[JOIN_AUD]);
        v.leeway = 0;
        Ok(decode::<JoinClaims>(token, &self.decoding, &v)?.claims)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn access_roundtrip() {
        let s = TokenSigner::new("secret");
        let uid = Uuid::new_v4();
        let t = s.sign_access(uid, 60).unwrap();
        assert_eq!(s.verify_access(&t).unwrap().sub, uid);
        // wrong audience family is rejected
        assert!(s.verify_join(&t).is_err());
    }

    #[test]
    fn join_roundtrip() {
        let s = TokenSigner::new("secret");
        let uid = Uuid::new_v4();
        let cid = Uuid::new_v4();
        let t = s.sign_join(uid, cid, "room-1", "sfu-1", 60).unwrap();
        let c = s.verify_join(&t).unwrap();
        assert_eq!(c.sub, uid);
        assert_eq!(c.room_id, "room-1");
    }

    #[test]
    fn expired_is_rejected() {
        let s = TokenSigner::new("secret");
        // Expired well beyond any clock-skew window; verify uses leeway = 0.
        let t = s.sign_access(Uuid::new_v4(), -120).unwrap();
        assert!(s.verify_access(&t).is_err());
    }
}
