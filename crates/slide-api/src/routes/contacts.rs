//! Contact sync + listing.
//!
//! The client uploads the phone numbers from its address book. We normalize to
//! E.164, look up which are Slide users, persist the resolved contacts for the
//! owner, and return the match results. We never store other people's address
//! books beyond the owner's own contact rows.

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};

use slide_core::{
    error::AppResult,
    models::{Contact, User},
    phone,
};

use crate::{auth::AuthUser, state::AppState};

#[derive(Deserialize)]
pub struct SyncBody {
    pub phones: Vec<String>,
    /// Optional parallel array of display names from the address book.
    #[serde(default)]
    pub names: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResult {
    pub phone: String,
    pub display_name: String,
    pub user_id: Option<uuid::Uuid>,
    pub on_slide: bool,
}

/// POST /contacts/sync
pub async fn sync(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<SyncBody>,
) -> AppResult<Json<Vec<SyncResult>>> {
    // Normalize, keeping a name alongside each (best-effort by index).
    let mut normalized: Vec<(String, String)> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for (i, raw) in body.phones.iter().enumerate() {
        if let Ok(e164) = phone::normalize_e164(raw, &state.cfg.default_region) {
            if seen.insert(e164.clone()) {
                let name = body.names.get(i).cloned().unwrap_or_default();
                normalized.push((e164, name));
            }
        }
    }

    if normalized.is_empty() {
        return Ok(Json(vec![]));
    }

    let phones: Vec<String> = normalized.iter().map(|(p, _)| p.clone()).collect();

    // Which of these are Slide users?
    let matches: Vec<User> = sqlx::query_as("SELECT * FROM users WHERE phone = ANY($1)")
        .bind(&phones)
        .fetch_all(&state.db)
        .await?;

    let mut by_phone = std::collections::HashMap::new();
    for u in &matches {
        by_phone.insert(u.phone.clone(), u.id);
    }

    // Persist resolved contacts for the owner (upsert per phone).
    let mut results = Vec::with_capacity(normalized.len());
    for (e164, name) in &normalized {
        let contact_user_id = by_phone.get(e164).copied();
        // Don't store yourself as your own contact.
        if contact_user_id == Some(uid) {
            results.push(SyncResult {
                phone: e164.clone(),
                display_name: name.clone(),
                user_id: contact_user_id,
                on_slide: true,
            });
            continue;
        }
        sqlx::query(
            "INSERT INTO contacts (owner_user_id, contact_user_id, phone, display_name)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (owner_user_id, phone)
             DO UPDATE SET contact_user_id = EXCLUDED.contact_user_id,
                           display_name = EXCLUDED.display_name",
        )
        .bind(uid)
        .bind(contact_user_id)
        .bind(e164)
        .bind(name)
        .execute(&state.db)
        .await?;

        results.push(SyncResult {
            phone: e164.clone(),
            display_name: name.clone(),
            user_id: contact_user_id,
            on_slide: contact_user_id.is_some(),
        });
    }

    Ok(Json(results))
}

/// GET /contacts — the owner's resolved contact list, name-sorted.
pub async fn list(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<Vec<Contact>>> {
    let contacts: Vec<Contact> = sqlx::query_as(
        "SELECT * FROM contacts WHERE owner_user_id = $1 ORDER BY display_name, phone",
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(contacts))
}
