//! Database models, mirrored 1:1 with the Postgres schema in `/migrations`.
//!
//! Enums map to native Postgres enum types of the same `snake_case` name.

use chrono::{DateTime, Utc};
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "call_type", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum CallType {
    OneToOne,
    Group,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "call_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum CallStatus {
    Ringing,
    Active,
    Ended,
    Missed,
    Declined,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "participant_state", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum ParticipantState {
    Invited,
    Ringing,
    Joined,
    Left,
    Declined,
}

// ── Tables ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct User {
    pub id: Uuid,
    pub phone: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
}

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

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Contact {
    pub id: Uuid,
    pub owner_user_id: Uuid,
    pub contact_user_id: Option<Uuid>,
    pub phone: String,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Call {
    pub id: Uuid,
    pub room_id: String,
    pub sfu_node_id: String,
    #[sqlx(rename = "type")]
    #[serde(rename = "type")]
    pub call_type: CallType,
    pub created_by: Uuid,
    pub status: CallStatus,
    pub started_at: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct CallParticipant {
    pub id: Uuid,
    pub call_id: Uuid,
    pub user_id: Uuid,
    pub state: ParticipantState,
    pub joined_at: Option<DateTime<Utc>>,
    pub left_at: Option<DateTime<Utc>>,
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
