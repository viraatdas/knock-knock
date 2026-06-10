//! /me, avatar upload, and device registration.

use axum::{
    extract::{Multipart, State},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};

use slide_core::{
    error::{AppError, AppResult},
    models::{Device, Platform, User},
};

use crate::{auth::AuthUser, state::AppState};

/// GET /me
pub async fn get_me(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<User>> {
    let user: User = sqlx::query_as("SELECT * FROM users WHERE id = $1")
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok(Json(user))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PatchMeBody {
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
}

/// PATCH /me — update display name and/or avatar. COALESCE keeps existing
/// values when a field is omitted.
pub async fn patch_me(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<PatchMeBody>,
) -> AppResult<Json<User>> {
    if let Some(name) = &body.display_name {
        if name.trim().is_empty() || name.len() > 80 {
            return Err(AppError::validation("display name must be 1–80 chars"));
        }
    }
    let user: User = sqlx::query_as(
        "UPDATE users
           SET display_name = COALESCE($2, display_name),
               avatar_url   = COALESCE($3, avatar_url)
         WHERE id = $1
         RETURNING *",
    )
    .bind(uid)
    .bind(body.display_name.as_deref())
    .bind(body.avatar_url.as_deref())
    .fetch_one(&state.db)
    .await?;
    Ok(Json(user))
}

/// POST /me/avatar — multipart image upload.
///
/// In dev (no S3 configured) the image is accepted and a stable placeholder
/// URL derived from the user id is stored, so the flow is exercisable without
/// object storage. With `S3_PUBLIC_BASE_URL` set this is where a real upload
/// to S3-compatible storage would happen.
pub async fn post_avatar(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    mut multipart: Multipart,
) -> AppResult<Json<Value>> {
    let mut received = false;
    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::bad_request(format!("bad multipart: {e}")))?
    {
        let data = field
            .bytes()
            .await
            .map_err(|e| AppError::bad_request(format!("bad upload: {e}")))?;
        if data.len() > 5 * 1024 * 1024 {
            return Err(AppError::validation("avatar must be ≤ 5MB"));
        }
        received = !data.is_empty();
        // TODO(storage): upload `data` to S3 and use the returned key.
    }
    if !received {
        return Err(AppError::bad_request("no image provided"));
    }

    let base = if state.cfg.s3_public_base_url.is_empty() {
        "https://avatars.slide.local".to_string()
    } else {
        state.cfg.s3_public_base_url.clone()
    };
    let avatar_url = format!("{base}/{uid}.jpg");

    sqlx::query("UPDATE users SET avatar_url = $2 WHERE id = $1")
        .bind(uid)
        .bind(&avatar_url)
        .execute(&state.db)
        .await?;

    Ok(Json(json!({ "avatarUrl": avatar_url })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceBody {
    pub push_token: String,
    pub platform: Platform,
    #[serde(default)]
    pub app_version: String,
}

/// POST /devices — upsert by push token.
pub async fn register_device(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<DeviceBody>,
) -> AppResult<Json<Device>> {
    if body.push_token.trim().is_empty() {
        return Err(AppError::validation("pushToken required"));
    }
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
    /// Device token (APNs/FCM) or the Web Push endpoint URL.
    pub push_token: String,
    /// 'apns' (standard alert token) | 'apns_voip' | 'fcm' | 'webpush'.
    pub kind: String,
    /// Web Push only: the client public key (base64url).
    #[serde(default)]
    pub p256dh: Option<String>,
    /// Web Push only: the client auth secret (base64url).
    #[serde(default)]
    pub auth: Option<String>,
    /// Optional, informational.
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub app_version: String,
}

/// POST /push/register — upsert a push subscription by (user_id, token).
///
/// Separate from POST /devices: subscriptions live in `push_subscriptions`,
/// which does not use the `platform` enum, so Web Push works without an enum
/// migration. The legacy /devices endpoint keeps functioning unchanged.
pub async fn register_push(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<PushRegisterBody>,
) -> AppResult<Json<Value>> {
    if body.push_token.trim().is_empty() {
        return Err(AppError::validation("pushToken required"));
    }
    let kind = body.kind.trim();
    if !matches!(kind, "apns" | "apns_voip" | "fcm" | "webpush") {
        return Err(AppError::validation(
            "kind must be one of apns|apns_voip|fcm|webpush",
        ));
    }
    if kind == "webpush" && (body.p256dh.is_none() || body.auth.is_none()) {
        return Err(AppError::validation(
            "webpush requires p256dh and auth keys",
        ));
    }
    let _ = &body.platform; // accepted for client convenience; not persisted.

    sqlx::query(
        "INSERT INTO push_subscriptions (user_id, kind, token, p256dh, auth, app_version)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (user_id, token)
         DO UPDATE SET kind = EXCLUDED.kind,
                       p256dh = EXCLUDED.p256dh,
                       auth = EXCLUDED.auth,
                       app_version = EXCLUDED.app_version,
                       updated_at = now()",
    )
    .bind(uid)
    .bind(kind)
    .bind(&body.push_token)
    .bind(body.p256dh.as_deref())
    .bind(body.auth.as_deref())
    .bind(&body.app_version)
    .execute(&state.db)
    .await?;

    Ok(Json(json!({ "ok": true })))
}
