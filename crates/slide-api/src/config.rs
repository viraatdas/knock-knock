//! Runtime configuration, loaded from environment (see `.env.example`).

use std::env;

use chrono_tz::Tz;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub redis_url: String,

    pub jwt_secret: String,
    pub access_ttl_secs: i64,
    pub refresh_ttl_secs: i64,

    pub otp_ttl_secs: i64,
    pub otp_max_attempts: i64,
    pub otp_pepper: String,
    pub default_region: String,

    pub sms_provider: String,
    pub twilio_account_sid: String,
    pub twilio_auth_token: String,
    pub twilio_from: String,
    /// AWS region for SNS (SMS). Defaults to us-east-1.
    pub aws_region: String,
    /// Firebase project id; when set, POST /auth/firebase verifies Firebase ID
    /// tokens (phone auth via the Firebase SDK on-device).
    pub firebase_project_id: String,
    /// Sender ID shown on the SMS where carriers support it (optional).
    pub sms_sender_id: String,
    /// DANGEROUS: when true, /auth/request-otp echoes the code in its response.
    /// MUST be false in production. Decoupled from sms_provider so a "console"
    /// provider never implies leaking the code.
    pub expose_dev_otp: bool,

    /// LiveKit media server. Every date session is minted as a LiveKit access
    /// token (signed with `livekit_api_secret`); the room name is the date id.
    /// `GET /dates/:id`-ish flows return 503 when this is unset.
    pub livekit_url: String,
    pub livekit_api_key: String,
    pub livekit_api_secret: String,

    pub api_bind: String,

    // ── Nightly session window (session.rs is the only place that reads these) ──
    pub session_tz: Tz,
    pub session_open_hour: u32,
    pub session_open_minute: u32,
    pub session_close_hour: u32,
    pub session_close_minute: u32,
    /// Dev/CI only: forces the session open at all times.
    pub session_always_open: bool,
    /// Length of a date, in seconds. Clamped to 30..900.
    pub date_seconds: i64,
    /// Matching radius, fixed (not user-adjustable).
    pub match_radius_miles: f64,

    // ── Review accounts (App Review must be able to test outside 7-8 PM PT) ──
    /// E.164 phone numbers that get review-account treatment.
    pub review_phones: Vec<String>,
    /// Fixed OTP code for review phones. Empty disables review login entirely.
    pub review_otp_code: String,
    /// The seeded "Sam" demo account review accounts match with. Read by
    /// `review::ensure_fixtures`.
    pub review_demo_phone: String,

    // ── Push notifications (APNs alert only; empty ⇒ disabled) ──
    /// The full contents of the .p8 auth key (PEM). May also be a file path.
    pub apns_key_id: String,
    pub apns_team_id: String,
    pub apns_key_p8: String,
    /// APNs topic for standard alert pushes = the bare bundle id (e.g.
    /// "app.exla.slide"). No CallKit/PushKit means there is no separate VoIP
    /// topic to track.
    pub apns_topic: String,
    /// "sandbox" | "prod". Defaults to "prod".
    pub apns_env: String,
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

fn var_u32(key: &str, default: u32) -> u32 {
    env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn var_bool(key: &str, default: bool) -> bool {
    env::var(key).ok().map(|v| v == "true").unwrap_or(default)
}

/// The old calling product used a separate VoIP-push topic, `<bundle-id>.voip`
/// (PushKit). That path is gone — no CallKit/PushKit anywhere in this app —
/// but the Fly secret `APNS_TOPIC` may still carry that old value. APNs
/// rejects a push whose `apns-topic` doesn't match a registered topic, so a
/// stale `.voip` suffix would silently break every alert push (match,
/// message, doors-open) in production. Strip it here, once, at boot, and log
/// so the stale secret gets noticed and fixed.
fn normalize_apns_topic(topic: String) -> String {
    match topic.strip_suffix(".voip") {
        Some(stripped) if !stripped.is_empty() => {
            tracing::warn!(
                original = %topic,
                normalized = %stripped,
                "config: APNS_TOPIC has a stale .voip suffix (VoIP pushes were removed); stripping it"
            );
            stripped.to_string()
        }
        _ => topic,
    }
}

/// True for the only two values `APNS_ENV` accepts. It picks the APNs host
/// (`push/apns.rs`), so a typo would quietly aim production pushes at the
/// sandbox host or the reverse, and Apple's answer would then be misleading.
pub fn apns_env_is_valid(value: &str) -> bool {
    matches!(value, "sandbox" | "prod")
}

impl Config {
    /// The `APNS_ENV` guard shared by `serve()` (at boot, whenever APNs
    /// credentials are present) and `push-test` (always), so the two cannot
    /// drift apart.
    pub fn check_apns_env(&self) -> anyhow::Result<()> {
        if apns_env_is_valid(&self.apns_env) {
            Ok(())
        } else {
            anyhow::bail!("APNS_ENV must be sandbox or prod, got {:?}", self.apns_env)
        }
    }

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

            otp_ttl_secs: var_i64("OTP_TTL_SECS", 300),
            otp_max_attempts: var_i64("OTP_MAX_ATTEMPTS", 5),
            otp_pepper: var("OTP_PEPPER", "dev-only-otp-pepper-change-me"),
            default_region: var("DEFAULT_REGION", "US"),

            sms_provider: var("SMS_PROVIDER", "console"),
            twilio_account_sid: var("TWILIO_ACCOUNT_SID", ""),
            twilio_auth_token: var("TWILIO_AUTH_TOKEN", ""),
            twilio_from: var("TWILIO_FROM_NUMBER", ""),
            aws_region: var("AWS_REGION", "us-east-1"),
            firebase_project_id: var("FIREBASE_PROJECT_ID", ""),
            sms_sender_id: var("SMS_SENDER_ID", ""),
            // Only ever true when explicitly opted in. Never derive from provider.
            expose_dev_otp: var("EXPOSE_DEV_OTP", "false") == "true",

            livekit_url: var("LIVEKIT_URL", ""),
            livekit_api_key: var("LIVEKIT_API_KEY", ""),
            livekit_api_secret: var("LIVEKIT_API_SECRET", ""),

            api_bind: var("API_BIND", "0.0.0.0:8080"),

            session_tz: var("SESSION_TZ", "America/Los_Angeles")
                .parse()
                .unwrap_or(chrono_tz::America::Los_Angeles),
            session_open_hour: var_u32("SESSION_OPEN_HOUR", 19),
            session_open_minute: var_u32("SESSION_OPEN_MINUTE", 0),
            session_close_hour: var_u32("SESSION_CLOSE_HOUR", 20),
            session_close_minute: var_u32("SESSION_CLOSE_MINUTE", 0),
            session_always_open: var_bool("SESSION_ALWAYS_OPEN", false),
            date_seconds: var_i64("DATE_SECONDS", 300).clamp(30, 900),
            match_radius_miles: var("MATCH_RADIUS_MILES", "75.0").parse().unwrap_or(75.0),

            review_phones: var("REVIEW_PHONES", "")
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
            review_otp_code: var("REVIEW_OTP_CODE", ""),
            review_demo_phone: var("REVIEW_DEMO_PHONE", "+16505550199"),

            apns_key_id: var("APNS_KEY_ID", ""),
            apns_team_id: var("APNS_TEAM_ID", ""),
            apns_key_p8: var("APNS_KEY_P8", ""),
            apns_topic: normalize_apns_topic(var("APNS_TOPIC", "app.exla.slide")),
            apns_env: var("APNS_ENV", "prod"),
        }
    }

    /// `true` only when the OTP code may be echoed in the API response. This is
    /// a SECURITY-sensitive override that must be explicitly enabled and is NOT
    /// implied by the SMS provider. In production this is false, so even if SMS
    /// delivery is misconfigured the code is never leaked to the caller.
    pub fn is_dev_sms(&self) -> bool {
        self.expose_dev_otp
    }

    /// `true` when a real (non-console) SMS provider is configured.
    pub fn has_real_sms_provider(&self) -> bool {
        matches!(self.sms_provider.as_str(), "sns" | "twilio")
    }

    pub fn is_review_phone(&self, e164: &str) -> bool {
        self.review_phones.iter().any(|p| p == e164)
    }

    /// `true` when review login is enabled at all (phones configured + a code
    /// to check them against).
    pub fn review_login_enabled(&self) -> bool {
        !self.review_phones.is_empty() && !self.review_otp_code.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::{apns_env_is_valid, normalize_apns_topic};

    #[test]
    fn apns_env_accepts_exactly_sandbox_and_prod() {
        assert!(apns_env_is_valid("sandbox"));
        assert!(apns_env_is_valid("prod"));
        for bad in ["", "production", "Sandbox", "prod ", "dev"] {
            assert!(!apns_env_is_valid(bad), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn strips_stale_voip_suffix_from_apns_topic() {
        // The exact stale value the Fly secret carries today.
        assert_eq!(
            normalize_apns_topic("app.exla.slide.voip".to_string()),
            "app.exla.slide"
        );
    }

    #[test]
    fn leaves_a_bare_bundle_id_topic_unchanged() {
        assert_eq!(
            normalize_apns_topic("app.exla.slide".to_string()),
            "app.exla.slide"
        );
    }

    #[test]
    fn leaves_empty_topic_unchanged() {
        // Empty disables APNs entirely (Apns::from_config checks is_empty());
        // stripping must never turn "" into something else.
        assert_eq!(normalize_apns_topic(String::new()), "");
    }
}
