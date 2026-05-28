//! Shared application state, cloned into every handler.

use std::sync::Arc;

use redis::aio::ConnectionManager;
use sqlx::PgPool;

use slide_core::jwt::TokenSigner;

use crate::{config::Config, hub::Hub, sms::SmsSender};

#[derive(Clone)]
pub struct AppState(pub Arc<Inner>);

pub struct Inner {
    pub cfg: Config,
    pub db: PgPool,
    pub redis: ConnectionManager,
    /// Signs/verifies access tokens (and opaque-token helpers live elsewhere).
    pub access_signer: TokenSigner,
    /// Signs SFU join tokens under the SFU's separate secret.
    pub sfu_signer: TokenSigner,
    pub sms: SmsSender,
    /// In-memory fan-out for the app-signaling WebSocket.
    pub hub: Hub,
}

impl std::ops::Deref for AppState {
    type Target = Inner;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl AppState {
    pub fn new(
        cfg: Config,
        db: PgPool,
        redis: ConnectionManager,
        sms: SmsSender,
        hub: Hub,
    ) -> Self {
        let access_signer = TokenSigner::new(&cfg.jwt_secret);
        let sfu_signer = TokenSigner::new(&cfg.sfu_jwt_secret);
        AppState(Arc::new(Inner {
            cfg,
            db,
            redis,
            access_signer,
            sfu_signer,
            sms,
            hub,
        }))
    }
}
