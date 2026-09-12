//! Matches + text chat (SPEC.md section 1.7).
//!
//! Responses are built with [`crate::views::match_summary`] (covers
//! `unreadCount`/`lastMessage`) and [`crate::views::MessageView`] (SPEC's
//! `Message`). Every `/matches/:id/*` handler goes through [`load_match`],
//! which enforces the two rules that apply everywhere in this file: the
//! caller must be `user_a` or `user_b` on the match, and an already-unmatched
//! match behaves as if it doesn't exist (404 either way, so a caller can't
//! probe for the difference between "not yours" and "no longer active").

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use slide_core::{
    error::{AppError, AppResult},
    models::MatchRow,
};

use crate::{
    auth::AuthUser, otp_store, state::AppState, views, views::MatchSummary, views::MessageView,
};

const MESSAGE_MAX_CHARS: usize = 2000;
const MESSAGE_RATE_LIMIT_PER_MIN: i64 = 30;
const MESSAGE_ALERT_TTL_SECS: u32 = 86_400;
const MESSAGE_ALERT_PREVIEW_CHARS: usize = 120;

/// Load a match by id and enforce membership + "still active" for `uid`.
/// Both failure cases are reported as plain 404s.
async fn load_match(state: &AppState, match_id: Uuid, uid: Uuid) -> AppResult<MatchRow> {
    let row: Option<MatchRow> = sqlx::query_as(
        "SELECT id, user_a, user_b, date_id, created_at, last_message_at, unmatched_at, unmatched_by
           FROM matches
          WHERE id = $1",
    )
    .bind(match_id)
    .fetch_optional(&state.db)
    .await?;

    let row = row.ok_or(AppError::NotFound)?;
    if row.user_a != uid && row.user_b != uid {
        return Err(AppError::NotFound);
    }
    if row.unmatched_at.is_some() {
        return Err(AppError::NotFound);
    }
    Ok(row)
}

fn partner_of(row: &MatchRow, uid: Uuid) -> Uuid {
    if row.user_a == uid {
        row.user_b
    } else {
        row.user_a
    }
}

/// GET /matches, ordered by `COALESCE(last_message_at, created_at) DESC`,
/// excluding unmatched pairs and pairs blocked in either direction.
pub async fn list_matches(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<Vec<MatchSummary>>> {
    let rows: Vec<MatchRow> = sqlx::query_as(
        "SELECT m.id, m.user_a, m.user_b, m.date_id, m.created_at, m.last_message_at,
                m.unmatched_at, m.unmatched_by
           FROM matches m
          WHERE (m.user_a = $1 OR m.user_b = $1)
            AND m.unmatched_at IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM blocks b
               WHERE (b.blocker_id = $1 AND b.blocked_id = CASE WHEN m.user_a = $1 THEN m.user_b ELSE m.user_a END)
                  OR (b.blocked_id = $1 AND b.blocker_id = CASE WHEN m.user_a = $1 THEN m.user_b ELSE m.user_a END)
            )
          ORDER BY COALESCE(m.last_message_at, m.created_at) DESC",
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;

    let mut summaries = Vec::with_capacity(rows.len());
    for row in &rows {
        summaries.push(views::match_summary(&state, row, uid).await?);
    }
    Ok(Json(summaries))
}

#[derive(Debug, Deserialize)]
pub struct ListMessagesQuery {
    pub before: Option<Uuid>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListMessagesResponse {
    /// Ascending by `createdAt`.
    pub messages: Vec<MessageView>,
    pub has_more: bool,
}

/// Given up to `limit + 1` rows already ordered newest-first (as the `before`
/// paging query returns them), split off the extra probe row as `hasMore`
/// and reverse the rest so the response reads oldest-first. Pure and DB-free
/// so paging math can be unit-tested without a database.
fn page_ascending(mut newest_first: Vec<MessageView>, limit: usize) -> (Vec<MessageView>, bool) {
    let has_more = newest_first.len() > limit;
    if has_more {
        newest_first.truncate(limit);
    }
    newest_first.reverse();
    (newest_first, has_more)
}

/// GET /matches/:id/messages?before=&limit=. `limit` clamps to 1..100;
/// `before` (a message id) pages backwards from just older than that message.
pub async fn list_messages(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(match_id): Path<Uuid>,
    Query(query): Query<ListMessagesQuery>,
) -> AppResult<Json<ListMessagesResponse>> {
    load_match(&state, match_id, uid).await?;

    let limit = query.limit.unwrap_or(50).clamp(1, 100);

    let rows: Vec<MessageView> = sqlx::query_as(
        "SELECT id, match_id, sender_id, body, created_at
           FROM messages
          WHERE match_id = $1
            AND ($2::uuid IS NULL
                 OR (created_at, id) < (SELECT created_at, id FROM messages WHERE id = $2))
          ORDER BY created_at DESC, id DESC
          LIMIT $3",
    )
    .bind(match_id)
    .bind(query.before)
    .bind(limit + 1)
    .fetch_all(&state.db)
    .await?;

    let (messages, has_more) = page_ascending(rows, limit as usize);
    Ok(Json(ListMessagesResponse { messages, has_more }))
}

#[derive(Debug, Deserialize)]
pub struct PostMessageBody {
    pub body: String,
}

/// Trim, require 1..2000 chars, and reject control characters other than
/// newline and tab. Returns the trimmed body to store.
fn validate_message_body(raw: &str) -> AppResult<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(AppError::validation("message can't be empty"));
    }
    if trimmed.chars().count() > MESSAGE_MAX_CHARS {
        return Err(AppError::validation("message is too long"));
    }
    if trimmed
        .chars()
        .any(|c| c.is_control() && c != '\n' && c != '\t')
    {
        return Err(AppError::validation(
            "message has characters that aren't allowed",
        ));
    }
    Ok(trimmed.to_string())
}

/// POST /matches/:id/messages. After insert: bump `matches.last_message_at`,
/// publish `message { matchId, message }` to both users (the sender's other
/// devices too), and — only when the partner has no live socket — send an
/// APNs alert (title = sender's display name, body = first 120 chars,
/// collapse-id = match id, default sound, ttl 1 day).
pub async fn post_message(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(match_id): Path<Uuid>,
    Json(body): Json<PostMessageBody>,
) -> AppResult<(StatusCode, Json<MessageView>)> {
    let match_row = load_match(&state, match_id, uid).await?;
    let partner_id = partner_of(&match_row, uid);
    let text = validate_message_body(&body.body)?;

    otp_store::rate_limit(
        &state,
        &format!("rl:messages:1m:{uid}"),
        MESSAGE_RATE_LIMIT_PER_MIN,
        60,
    )
    .await?;

    let message: MessageView = sqlx::query_as(
        "INSERT INTO messages (match_id, sender_id, body)
         VALUES ($1, $2, $3)
         RETURNING id, match_id, sender_id, body, created_at",
    )
    .bind(match_id)
    .bind(uid)
    .bind(&text)
    .fetch_one(&state.db)
    .await?;

    sqlx::query("UPDATE matches SET last_message_at = $1 WHERE id = $2")
        .bind(message.created_at)
        .bind(match_id)
        .execute(&state.db)
        .await?;

    let event = json!({ "type": "message", "matchId": match_id, "message": message });
    state.hub.publish_many(&[uid, partner_id], &event).await;

    if !state.hub.is_online(partner_id).await {
        let sender_name: Option<String> =
            sqlx::query_scalar("SELECT display_name FROM users WHERE id = $1")
                .bind(uid)
                .fetch_one(&state.db)
                .await?;
        let title = sender_name
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| "New message".to_string());
        let preview: String = text.chars().take(MESSAGE_ALERT_PREVIEW_CHARS).collect();

        let mut data = serde_json::Map::new();
        data.insert("type".to_string(), json!("message"));
        data.insert("matchId".to_string(), json!(match_id));

        state
            .push
            .notify_alert(
                &state.db,
                partner_id,
                &title,
                &preview,
                Some(&match_id.to_string()),
                None,
                MESSAGE_ALERT_TTL_SECS,
                Some(data),
            )
            .await;
    }

    Ok((StatusCode::CREATED, Json(message)))
}

/// POST /matches/:id/read. Upserts `match_reads.last_read_at = now()`.
pub async fn mark_read(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(match_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    load_match(&state, match_id, uid).await?;

    sqlx::query(
        "INSERT INTO match_reads (match_id, user_id, last_read_at)
         VALUES ($1, $2, now())
         ON CONFLICT (match_id, user_id) DO UPDATE SET last_read_at = excluded.last_read_at",
    )
    .bind(match_id)
    .bind(uid)
    .execute(&state.db)
    .await?;

    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /matches/:id. Sets `unmatched_at`/`unmatched_by`, publishes
/// `match_removed { matchId }` to the partner only.
pub async fn unmatch(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(match_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let match_row = load_match(&state, match_id, uid).await?;
    let partner_id = partner_of(&match_row, uid);

    sqlx::query("UPDATE matches SET unmatched_at = now(), unmatched_by = $1 WHERE id = $2")
        .bind(uid)
        .bind(match_id)
        .execute(&state.db)
        .await?;

    state
        .hub
        .publish(
            partner_id,
            json!({ "type": "match_removed", "matchId": match_id }),
        )
        .await;

    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use uuid::Uuid;

    use super::{page_ascending, validate_message_body, MESSAGE_MAX_CHARS};
    use crate::views::MessageView;

    fn msg(created_offset_secs: i64) -> MessageView {
        MessageView {
            id: Uuid::new_v4(),
            match_id: Uuid::new_v4(),
            sender_id: Uuid::new_v4(),
            body: "hi".to_string(),
            created_at: Utc::now() + chrono::Duration::seconds(created_offset_secs),
        }
    }

    // ── validate_message_body ───────────────────────────────────────────────

    #[test]
    fn trims_and_accepts_a_normal_message() {
        let out = validate_message_body("  hey there  ").unwrap();
        assert_eq!(out, "hey there");
    }

    #[test]
    fn rejects_empty_after_trim() {
        assert!(validate_message_body("   ").is_err());
        assert!(validate_message_body("").is_err());
    }

    #[test]
    fn rejects_over_the_length_limit() {
        let long = "a".repeat(MESSAGE_MAX_CHARS + 1);
        assert!(validate_message_body(&long).is_err());
    }

    #[test]
    fn accepts_exactly_the_length_limit() {
        let exact = "a".repeat(MESSAGE_MAX_CHARS);
        assert!(validate_message_body(&exact).is_ok());
    }

    #[test]
    fn allows_newline_and_tab() {
        let out = validate_message_body("line one\nline two\tindented").unwrap();
        assert_eq!(out, "line one\nline two\tindented");
    }

    #[test]
    fn rejects_other_control_characters() {
        // NUL and a raw carriage return are control chars other than \n/\t.
        assert!(validate_message_body("hi\0there").is_err());
        assert!(validate_message_body("hi\rthere").is_err());
    }

    // ── page_ascending ───────────────────────────────────────────────────────

    #[test]
    fn returns_no_more_when_under_the_limit() {
        // Newest-first input, as the DB query returns it.
        let rows = vec![msg(-1), msg(-2), msg(-3)];
        let (page, has_more) = page_ascending(rows, 5);
        assert!(!has_more);
        assert_eq!(page.len(), 3);
        // Reversed to ascending (oldest first).
        assert!(page[0].created_at < page[1].created_at);
        assert!(page[1].created_at < page[2].created_at);
    }

    #[test]
    fn signals_has_more_and_drops_the_probe_row() {
        // limit=2, so 3 rows means one extra probe row came back.
        let rows = vec![msg(-1), msg(-2), msg(-3)];
        let (page, has_more) = page_ascending(rows, 2);
        assert!(has_more);
        assert_eq!(page.len(), 2);
        assert!(page[0].created_at < page[1].created_at);
    }

    #[test]
    fn empty_input_has_no_more() {
        let (page, has_more) = page_ascending(vec![], 50);
        assert!(page.is_empty());
        assert!(!has_more);
    }
}
