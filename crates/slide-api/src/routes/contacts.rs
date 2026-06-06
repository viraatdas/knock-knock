//! Contact sync + listing.
//!
//! The client uploads the phone numbers from its address book. We normalize to
//! E.164, look up which are Slide users, persist the resolved contacts for the
//! owner, and return the match results. We never store other people's address
//! books beyond the owner's own contact rows.

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};

use slide_core::{error::AppResult, models::User, phone};

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

fn display_name_for_contact(local_name: &str, phone: &str, matched: Option<&User>) -> String {
    let local = local_name.trim();
    if !local.is_empty() && local != phone {
        return local_name.to_string();
    }
    matched
        .and_then(|u| u.display_name.as_deref())
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| local_name.to_string())
}

/// Link previously-synced contact rows to a user that just signed up.
///
/// Contacts can be uploaded before the phone number belongs to a Slide user.
/// Those rows are intentionally stored with a null contact_user_id, so we repair
/// them when the matching account appears instead of waiting for every owner to
/// re-upload their address book.
pub(crate) async fn link_existing_contacts_for_user(
    state: &AppState,
    user_id: uuid::Uuid,
    phone: &str,
) -> AppResult<u64> {
    let result = sqlx::query(
        "UPDATE contacts
         SET contact_user_id = $1
         WHERE phone = $2
           AND owner_user_id <> $1
           AND contact_user_id IS NULL",
    )
    .bind(user_id)
    .bind(phone)
    .execute(&state.db)
    .await?;

    Ok(result.rows_affected())
}

async fn repair_owner_contacts(state: &AppState, owner_user_id: uuid::Uuid) -> AppResult<u64> {
    let result = sqlx::query(
        "UPDATE contacts c
         SET contact_user_id = u.id
         FROM users u
         WHERE c.owner_user_id = $1
           AND c.contact_user_id IS NULL
           AND c.phone = u.phone
           AND u.id <> c.owner_user_id",
    )
    .bind(owner_user_id)
    .execute(&state.db)
    .await?;

    Ok(result.rows_affected())
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
    for u in matches {
        by_phone.insert(u.phone.clone(), u);
    }

    // Persist resolved contacts for the owner (upsert per phone).
    let mut results = Vec::with_capacity(normalized.len());
    for (e164, name) in &normalized {
        let matched = by_phone.get(e164);
        let contact_user_id = matched.map(|u| u.id);
        let display_name = display_name_for_contact(name, e164, matched);
        // Don't store yourself as your own contact.
        if contact_user_id == Some(uid) {
            results.push(SyncResult {
                phone: e164.clone(),
                display_name,
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
                           -- Never overwrite a good name with a blank one (a
                           -- client that omits names must not wipe stored names).
                           display_name = COALESCE(
                               NULLIF(EXCLUDED.display_name, ''),
                               contacts.display_name)",
        )
        .bind(uid)
        .bind(contact_user_id)
        .bind(e164)
        .bind(name)
        .execute(&state.db)
        .await?;

        results.push(SyncResult {
            phone: e164.clone(),
            display_name,
            user_id: contact_user_id,
            on_slide: contact_user_id.is_some(),
        });
    }

    Ok(Json(results))
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct ContactView {
    pub id: uuid::Uuid,
    pub owner_user_id: uuid::Uuid,
    pub contact_user_id: Option<uuid::Uuid>,
    pub phone: String,
    pub display_name: String,
    /// The matched Slide user's avatar (if they're on Slide and have one).
    pub avatar_url: Option<String>,
}

/// GET /contacts — the owner's resolved contact list, name-sorted, with the
/// matched user's avatar joined in so on-Slide contacts show their photo.
pub async fn list(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<Vec<ContactView>>> {
    if let Err(err) = repair_owner_contacts(&state, uid).await {
        tracing::warn!(error = ?err, owner_user_id = %uid, "failed to repair owner contacts");
    }

    let contacts: Vec<ContactView> = sqlx::query_as(
        "SELECT c.id, c.owner_user_id, c.contact_user_id, c.phone,
                COALESCE(NULLIF(NULLIF(c.display_name, c.phone), ''), NULLIF(u.display_name, ''), c.display_name) AS display_name,
                u.avatar_url AS avatar_url
         FROM contacts c
         LEFT JOIN users u ON u.id = c.contact_user_id
         WHERE c.owner_user_id = $1
         ORDER BY COALESCE(NULLIF(NULLIF(c.display_name, c.phone), ''), NULLIF(u.display_name, ''), c.display_name), c.phone",
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(contacts))
}
