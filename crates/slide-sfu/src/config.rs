//! SFU node configuration from env.

use std::env;

#[derive(Clone)]
pub struct SfuConfig {
    pub bind: String,
    pub node_id: String,
    /// Shared secret used by the control plane to mint join tokens. The SFU
    /// validates incoming join tokens against this.
    pub sfu_jwt_secret: String,
    pub turn_uris: Vec<String>,
    pub turn_shared_secret: String,
    pub turn_cred_ttl_secs: i64,
    /// Public UDP IP to advertise in ICE candidates (1:1 NAT on Fly/cloud).
    #[allow(dead_code)]
    pub public_ip: Option<String>,
}

fn var(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

impl SfuConfig {
    pub fn from_env() -> Self {
        Self {
            bind: var("SFU_BIND", "0.0.0.0:9000"),
            node_id: var("SFU_NODE_ID", "sfu-local-1"),
            sfu_jwt_secret: var("SFU_JWT_SECRET", "dev-only-sfu-secret-change-me"),
            turn_uris: var("TURN_URIS", "")
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
            turn_shared_secret: var("TURN_SHARED_SECRET", "dev-only-turn-secret-change-me"),
            turn_cred_ttl_secs: var("TURN_CRED_TTL_SECS", "600").parse().unwrap_or(600),
            public_ip: env::var("SFU_PUBLIC_IP").ok().filter(|s| !s.is_empty()),
        }
    }
}
