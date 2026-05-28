//! Opaque refresh-token lifecycle (issue / rotate / revoke).
//!
//! A refresh token is a high-entropy random string handed to the client. Only
//! its SHA-256 hash is stored, so a database leak can't be used to mint access
//! tokens. Rotation revokes the presented token and issues a fresh one.

use chrono::{DateTime, Duration, Utc};
use rand::RngCore;
use sha2::{Digest, Sha256};
use uuid::Uuid;

use slide_core::error::{AppError, AppResult};

use crate::state::AppState;

fn hash_token(token: &str) -> String {
    let mut h = Sha256::new();
    h.update(token.as_bytes());
    hex::encode(h.finalize())
}

fn random_token() -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Issue a new refresh token for `user_id`, persisting only its hash.
pub async fn issue(state: &AppState, user_id: Uuid) -> AppResult<String> {
    let token = random_token();
    let token_hash = hash_token(&token);
    let expires_at = Utc::now() + Duration::seconds(state.cfg.refresh_ttl_secs);

    sqlx::query("INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)")
        .bind(user_id)
        .bind(&token_hash)
        .bind(expires_at)
        .execute(&state.db)
        .await?;

    Ok(token)
}

/// The row we read when validating a presented refresh token.
#[derive(sqlx::FromRow)]
struct RefreshRow {
    id: Uuid,
    user_id: Uuid,
    expires_at: DateTime<Utc>,
    revoked_at: Option<DateTime<Utc>>,
}

/// Validate a presented refresh token, rotate it (revoke old, issue new), and
/// return `(user_id, new_refresh_token)`.
pub async fn rotate(state: &AppState, token: &str) -> AppResult<(Uuid, String)> {
    let token_hash = hash_token(token);

    let row: Option<RefreshRow> = sqlx::query_as(
        "SELECT id, user_id, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = $1",
    )
    .bind(&token_hash)
    .fetch_optional(&state.db)
    .await?;

    let row = row.ok_or(AppError::Unauthorized)?;
    if row.revoked_at.is_some() || row.expires_at < Utc::now() {
        return Err(AppError::Unauthorized);
    }

    // Revoke the presented token.
    sqlx::query("UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1")
        .bind(row.id)
        .execute(&state.db)
        .await?;

    let new_token = issue(state, row.user_id).await?;
    Ok((row.user_id, new_token))
}

/// Revoke a refresh token (logout). No-op if it doesn't exist.
pub async fn revoke(state: &AppState, token: &str) -> AppResult<()> {
    let token_hash = hash_token(token);
    sqlx::query(
        "UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL",
    )
    .bind(&token_hash)
    .execute(&state.db)
    .await?;
    Ok(())
}
