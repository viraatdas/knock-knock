//! Device registration and push-token registration.
//!
//! `GET`/`PATCH /me` and the photo endpoints moved to `routes::profile`
//! (SPEC.md section 1.5) along with the rest of the profile surface; this
//! file keeps the installation-identifying endpoints that didn't change
//! shape. The old `POST /me/avatar` is gone — profile photos are
//! `PUT /me/photo` now.

use axum::{extract::State, http::StatusCode, Json};
use serde::Deserialize;
use serde_json::{json, Value};

use slide_core::{
    error::{AppError, AppResult},
    models::{Device, Platform},
};

use crate::{auth::AuthUser, state::AppState};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceBody {
    pub push_token: String,
    pub platform: Platform,
    #[serde(default)]
    pub app_version: String,
}

/// POST /devices — upsert by push token. Kept for client compatibility; it
/// does not touch `push_subscriptions` (that's `/push/register`'s job).
pub async fn register_device(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<DeviceBody>,
) -> AppResult<Json<Device>> {
    validate_native_token(&body.push_token)?;
    let device: Device = sqlx::query_as(
        "INSERT INTO devices (user_id, push_token, platform, app_version)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (push_token)
         DO UPDATE SET user_id = EXCLUDED.user_id,
                       platform = EXCLUDED.platform,
                       app_version = EXCLUDED.app_version,
                       updated_at = now()
         RETURNING *",
    )
    .bind(uid)
    .bind(&body.push_token)
    .bind(body.platform)
    .bind(&body.app_version)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(device))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushRegisterBody {
    /// APNs device token.
    pub push_token: String,
    /// Only "apns" is accepted (no CallKit/PushKit, no Android/web client
    /// for this product).
    pub kind: String,
    /// Optional, informational.
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub app_version: String,
}

/// POST /push/register — transfer/upsert a globally owned push endpoint.
pub async fn register_push(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<PushRegisterBody>,
) -> AppResult<Json<Value>> {
    let kind = body.kind.trim();
    if kind != "apns" {
        return Err(AppError::validation("kind must be apns"));
    }
    validate_native_token(&body.push_token)?;
    let _ = &body.platform; // accepted for client convenience; not persisted.

    sqlx::query(
        "INSERT INTO push_subscriptions (user_id, kind, token, app_version)
         VALUES ($1, 'apns', $2, $3)
         ON CONFLICT (token)
         DO UPDATE SET user_id = EXCLUDED.user_id,
                       kind = 'apns',
                       app_version = EXCLUDED.app_version,
                       updated_at = now()",
    )
    .bind(uid)
    .bind(&body.push_token)
    .bind(&body.app_version)
    .execute(&state.db)
    .await?;

    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushUnregisterBody {
    pub push_token: String,
}

/// DELETE /push/register — detach one installation on logout/token rotation.
/// Ownership is checked so one account cannot unregister another's endpoint.
pub async fn unregister_push(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<PushUnregisterBody>,
) -> AppResult<StatusCode> {
    if body.push_token.trim().is_empty() || body.push_token.len() > 4096 {
        return Err(AppError::validation("valid pushToken required"));
    }

    let mut tx = state.db.begin().await?;
    sqlx::query("DELETE FROM push_subscriptions WHERE user_id = $1 AND token = $2")
        .bind(uid)
        .bind(&body.push_token)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM devices WHERE user_id = $1 AND push_token = $2")
        .bind(uid)
        .bind(&body.push_token)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// APNs device tokens are 64+ hex characters. Applies to both `/devices` and
/// `/push/register` now that this product is iOS-only.
fn validate_native_token(token: &str) -> AppResult<()> {
    let token = token.trim();
    if token.is_empty()
        || token.len() > 4096
        || token.len() < 32
        || !token.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(AppError::validation("invalid pushToken"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::validate_native_token;

    #[test]
    fn rejects_path_injection() {
        assert!(validate_native_token("abc/../../device").is_err());
    }

    #[test]
    fn accepts_hex_token() {
        assert!(validate_native_token(&"a".repeat(64)).is_ok());
    }

    #[test]
    fn rejects_short_or_non_hex() {
        assert!(validate_native_token("not-hex").is_err());
        assert!(validate_native_token(&"a".repeat(10)).is_err());
    }
}
