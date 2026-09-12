//! Database models, mirrored 1:1 with the Postgres schema in `/migrations`.
//!
//! Enums map to native Postgres enum types of the same `snake_case` name.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ── Enums ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "platform", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum Platform {
    Ios,
    Android,
}

// ── Tables ──────────────────────────────────────────────────────────────────

/// The `users` row, minus the `photo` column.
///
/// `photo` holds up to 600 KB of JPEG bytes. Every query against `users` MUST
/// list columns explicitly with [`USER_COLUMNS`] (never `SELECT *`) so an
/// ordinary profile/auth lookup never drags photo bytes over the wire. The
/// photo route (`GET /users/:id/photo`) selects `photo` on its own.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct User {
    pub id: Uuid,
    pub phone: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,

    // ── Speed-date profile + preferences (0008_speed_date.sql) ──
    pub birthdate: Option<NaiveDate>,
    /// 'woman' | 'man' | 'nonbinary'.
    pub gender: Option<String>,
    /// Subset of {'woman','man','nonbinary'} this user wants to see.
    pub interested_in: Vec<String>,
    pub age_min: i16,
    pub age_max: i16,
    pub bio: String,
    /// Coarse (rounded to 2 decimals, ~1km) location, or None if never set.
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub location_updated_at: Option<DateTime<Utc>>,
    /// Set whenever `photo` is written, cleared (along with `photo`) on
    /// delete. `photo_updated_at.is_some()` is the source of truth for
    /// "has a photo" — never select the `photo` column itself to answer that.
    pub photo_updated_at: Option<DateTime<Utc>>,
    /// Set once, the first time displayName/birthdate/gender/interestedIn are
    /// all present. Views re-derive `profileComplete` from those fields
    /// directly rather than trusting this column, since later edits can't
    /// unset it; it's kept mainly for analytics/debugging.
    pub profile_completed_at: Option<DateTime<Utc>>,
    pub is_review_account: bool,
}

/// Explicit column list for every `users` query. Deliberately omits `photo`
/// (see [`User`]) so an ordinary lookup can never pull photo bytes.
pub const USER_COLUMNS: &str = "id, phone, display_name, avatar_url, created_at, last_seen_at, \
    birthdate, gender, interested_in, age_min, age_max, bio, lat, lng, location_updated_at, \
    photo_updated_at, profile_completed_at, is_review_account";

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    pub id: Uuid,
    pub user_id: Uuid,
    pub push_token: String,
    pub platform: Platform,
    pub app_version: String,
    pub updated_at: DateTime<Utc>,
}

/// One side of tonight's 5-minute video date. `session_date` is the PT
/// calendar date the date belongs to (see `session.rs`); `room_id` is the
/// LiveKit room name (= `id` as a string).
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct DateRow {
    pub id: Uuid,
    pub user_a: Uuid,
    pub user_b: Uuid,
    pub room_id: String,
    pub session_date: NaiveDate,
    pub started_at: DateTime<Utc>,
    pub ends_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    /// 'timeout' | 'left' | 'blocked'.
    pub end_reason: Option<String>,
    pub decision_a: Option<bool>,
    pub decided_a_at: Option<DateTime<Utc>>,
    pub decision_b: Option<bool>,
    pub decided_b_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// A mutual "keep talking", unlocking text chat. `user_a < user_b` always.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct MatchRow {
    pub id: Uuid,
    pub user_a: Uuid,
    pub user_b: Uuid,
    pub date_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub last_message_at: Option<DateTime<Utc>>,
    pub unmatched_at: Option<DateTime<Utc>>,
    pub unmatched_by: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct MessageRow {
    pub id: Uuid,
    pub match_id: Uuid,
    pub sender_id: Uuid,
    pub body: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct BlockRow {
    pub blocker_id: Uuid,
    pub blocked_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct ReportRow {
    pub id: Uuid,
    pub reporter_id: Uuid,
    pub reported_id: Uuid,
    /// 'inappropriate' | 'harassment' | 'fake' | 'underage' | 'other'.
    pub reason: String,
    pub details: String,
    pub date_id: Option<Uuid>,
    pub match_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

/// Opaque, rotating refresh token. Only the hash is ever stored.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct RefreshToken {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token_hash: String,
    pub device_id: Option<Uuid>,
    pub expires_at: DateTime<Utc>,
    pub revoked_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}
