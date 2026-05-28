//! Runtime configuration, loaded from environment (see `.env.example`).

use std::env;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub redis_url: String,

    pub jwt_secret: String,
    pub access_ttl_secs: i64,
    pub refresh_ttl_secs: i64,
    pub join_ttl_secs: i64,

    pub otp_ttl_secs: i64,
    pub otp_max_attempts: i64,
    pub otp_pepper: String,
    pub default_region: String,

    pub sms_provider: String,
    pub twilio_account_sid: String,
    pub twilio_auth_token: String,
    pub twilio_from: String,

    pub sfu_public_url: String,
    pub sfu_jwt_secret: String,
    pub sfu_node_id: String,

    pub turn_uris: Vec<String>,
    pub turn_shared_secret: String,
    pub turn_cred_ttl_secs: i64,

    // Reserved for the real S3 avatar upload path (routes::users::post_avatar).
    #[allow(dead_code)]
    pub s3_bucket: String,
    pub s3_public_base_url: String,

    pub api_bind: String,
}

fn var(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

fn var_i64(key: &str, default: i64) -> i64 {
    env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            database_url: var(
                "DATABASE_URL",
                "postgres://slide:slide@localhost:5432/slide",
            ),
            redis_url: var("REDIS_URL", "redis://localhost:6379"),

            jwt_secret: var("JWT_SECRET", "dev-only-insecure-secret-change-me"),
            access_ttl_secs: var_i64("ACCESS_TOKEN_TTL_SECS", 900),
            refresh_ttl_secs: var_i64("REFRESH_TOKEN_TTL_SECS", 5_184_000),
            join_ttl_secs: var_i64("JOIN_TOKEN_TTL_SECS", 300),

            otp_ttl_secs: var_i64("OTP_TTL_SECS", 300),
            otp_max_attempts: var_i64("OTP_MAX_ATTEMPTS", 5),
            otp_pepper: var("OTP_PEPPER", "dev-only-otp-pepper-change-me"),
            default_region: var("DEFAULT_REGION", "US"),

            sms_provider: var("SMS_PROVIDER", "console"),
            twilio_account_sid: var("TWILIO_ACCOUNT_SID", ""),
            twilio_auth_token: var("TWILIO_AUTH_TOKEN", ""),
            twilio_from: var("TWILIO_FROM_NUMBER", ""),

            sfu_public_url: var("SFU_PUBLIC_URL", "ws://localhost:9000"),
            sfu_jwt_secret: var("SFU_JWT_SECRET", "dev-only-sfu-secret-change-me"),
            sfu_node_id: var("SFU_NODE_ID", "sfu-local-1"),

            turn_uris: var("TURN_URIS", "")
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
            turn_shared_secret: var("TURN_SHARED_SECRET", "dev-only-turn-secret-change-me"),
            turn_cred_ttl_secs: var_i64("TURN_CRED_TTL_SECS", 600),

            s3_bucket: var("S3_BUCKET", "slide-avatars"),
            s3_public_base_url: var("S3_PUBLIC_BASE_URL", ""),

            api_bind: var("API_BIND", "0.0.0.0:8080"),
        }
    }

    /// `true` in dev mode (SMS printed to logs, dev OTP returned in responses).
    pub fn is_dev_sms(&self) -> bool {
        self.sms_provider == "console"
    }
}
