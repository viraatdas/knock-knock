//! Redis-backed OTP challenge storage and rate limiting.

use redis::AsyncCommands;
use serde::{Deserialize, Serialize};

use slide_core::error::{AppError, AppResult};

use crate::state::AppState;

#[derive(Serialize, Deserialize)]
struct StoredOtp {
    code_hash: String,
    attempts: i64,
}

fn otp_key(phone: &str) -> String {
    format!("otp:{phone}")
}

/// Store a fresh OTP challenge for `phone`, overwriting any existing one.
pub async fn put_otp(state: &AppState, phone: &str, code_hash: &str) -> AppResult<()> {
    let mut conn = state.redis.clone();
    let val = serde_json::to_string(&StoredOtp {
        code_hash: code_hash.to_string(),
        attempts: 0,
    })?;
    conn.set_ex::<_, _, ()>(otp_key(phone), val, state.cfg.otp_ttl_secs as u64)
        .await
        .map_err(|e| AppError::Internal(e.into()))?;
    Ok(())
}

/// Outcome of an OTP verification attempt.
pub enum OtpCheck {
    Ok,
    Wrong,
    Expired,
    TooManyAttempts,
}

/// Check a submitted code, incrementing the attempt counter. On success or
/// exhaustion the challenge is consumed (deleted).
pub async fn check_otp(state: &AppState, phone: &str, code: &str) -> AppResult<OtpCheck> {
    let mut conn = state.redis.clone();
    let key = otp_key(phone);

    let raw: Option<String> = conn
        .get(&key)
        .await
        .map_err(|e| AppError::Internal(e.into()))?;
    let Some(raw) = raw else {
        return Ok(OtpCheck::Expired);
    };
    let mut stored: StoredOtp = serde_json::from_str(&raw)?;

    if stored.attempts >= state.cfg.otp_max_attempts {
        let _: () = conn.del(&key).await.unwrap_or(());
        return Ok(OtpCheck::TooManyAttempts);
    }

    let ok = slide_core::otp::verify_code(code, phone, &state.cfg.otp_pepper, &stored.code_hash);
    if ok {
        let _: () = conn.del(&key).await.unwrap_or(());
        Ok(OtpCheck::Ok)
    } else {
        stored.attempts += 1;
        // Preserve the remaining TTL while bumping the attempt count.
        let ttl: i64 = conn.ttl(&key).await.unwrap_or(state.cfg.otp_ttl_secs);
        let ttl = ttl.max(1) as u64;
        let val = serde_json::to_string(&stored)?;
        let _: () = conn.set_ex(&key, val, ttl).await.unwrap_or(());
        Ok(OtpCheck::Wrong)
    }
}

/// Sliding-window-ish rate limit: increment a counter under `key`, setting a
/// TTL on first hit. Returns `Err(RateLimited)` if the count exceeds `limit`.
pub async fn rate_limit(
    state: &AppState,
    key: &str,
    limit: i64,
    window_secs: i64,
) -> AppResult<()> {
    let mut conn = state.redis.clone();
    let count: i64 = conn
        .incr(key, 1)
        .await
        .map_err(|e| AppError::Internal(e.into()))?;
    if count == 1 {
        let _: () = conn.expire(key, window_secs).await.unwrap_or(());
    }
    if count > limit {
        let ttl: i64 = conn.ttl(key).await.unwrap_or(window_secs);
        return Err(AppError::RateLimited {
            retry_after_secs: ttl.max(1) as u64,
        });
    }
    Ok(())
}
