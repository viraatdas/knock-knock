//! Block / unblock / report (SPEC.md section 1.8).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use serde_json::json;
use uuid::Uuid;

use slide_core::error::{AppError, AppResult};

use crate::{auth::AuthUser, state::AppState};

const REPORT_REASONS: [&str; 5] = ["inappropriate", "harassment", "fake", "underage", "other"];
const REPORT_DETAILS_MAX_CHARS: usize = 1000;

async fn user_exists(state: &AppState, id: Uuid) -> AppResult<bool> {
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)")
        .bind(id)
        .fetch_one(&state.db)
        .await?;
    Ok(exists)
}

/// POST /users/:id/block. Inserts into `blocks` (idempotent), then in one
/// transaction: unmatches any active match between the two (publishing
/// `match_removed` to the other side only) and ends any open date between
/// them with `end_reason='blocked'` — but the *other* side only ever hears
/// `date_ended` with reason `"left"`. A block is never revealed to the
/// blocked side, and the blocker gets no events for their own action.
pub async fn block_user(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(target_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    if target_id == uid {
        return Err(AppError::bad_request("you can't block yourself"));
    }
    if !user_exists(&state, target_id).await? {
        return Err(AppError::NotFound);
    }

    let mut tx = state.db.begin().await?;

    sqlx::query(
        "INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)
         ON CONFLICT (blocker_id, blocked_id) DO NOTHING",
    )
    .bind(uid)
    .bind(target_id)
    .execute(&mut *tx)
    .await?;

    let unmatched_id: Option<Uuid> = sqlx::query_scalar(
        "UPDATE matches
            SET unmatched_at = now(), unmatched_by = $1
          WHERE ((user_a = $1 AND user_b = $2) OR (user_a = $2 AND user_b = $1))
            AND unmatched_at IS NULL
        RETURNING id",
    )
    .bind(uid)
    .bind(target_id)
    .fetch_optional(&mut *tx)
    .await?;

    let ended_date_id: Option<Uuid> = sqlx::query_scalar(
        "UPDATE dates
            SET ended_at = now(), end_reason = 'blocked'
          WHERE ((user_a = $1 AND user_b = $2) OR (user_a = $2 AND user_b = $1))
            AND ended_at IS NULL
        RETURNING id",
    )
    .bind(uid)
    .bind(target_id)
    .fetch_optional(&mut *tx)
    .await?;

    tx.commit().await?;

    if let Some(match_id) = unmatched_id {
        state
            .hub
            .publish(
                target_id,
                json!({ "type": "match_removed", "matchId": match_id }),
            )
            .await;
    }
    if let Some(date_id) = ended_date_id {
        state
            .hub
            .publish(
                target_id,
                json!({ "type": "date_ended", "dateId": date_id, "reason": "left" }),
            )
            .await;
    }

    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /users/:id/block. Removing a block that doesn't exist is not an
/// error — this is idempotent.
pub async fn unblock_user(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(target_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    sqlx::query("DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2")
        .bind(uid)
        .bind(target_id)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportBody {
    /// One of 'inappropriate' | 'harassment' | 'fake' | 'underage' | 'other'.
    pub reason: String,
    #[serde(default)]
    pub details: Option<String>,
    pub date_id: Option<Uuid>,
    pub match_id: Option<Uuid>,
}

/// POST /users/:id/report. `reason` must be one of the enum values; `details`
/// is trimmed and capped at 1000 chars.
pub async fn report_user(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(target_id): Path<Uuid>,
    Json(body): Json<ReportBody>,
) -> AppResult<StatusCode> {
    if !REPORT_REASONS.contains(&body.reason.as_str()) {
        return Err(AppError::validation(
            "reason must be one of: inappropriate, harassment, fake, underage, other",
        ));
    }
    if !user_exists(&state, target_id).await? {
        return Err(AppError::NotFound);
    }

    let details = validate_report_details(&body.details.unwrap_or_default())?;

    sqlx::query(
        "INSERT INTO reports (reporter_id, reported_id, reason, details, date_id, match_id)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(uid)
    .bind(target_id)
    .bind(&body.reason)
    .bind(&details)
    .bind(body.date_id)
    .bind(body.match_id)
    .execute(&state.db)
    .await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Trim, cap at 1000 chars, and reject control characters other than
/// newline/tab (same filter as `chat::validate_message_body`) so a report
/// can't carry rendering-glitch or spoofing characters (bidi overrides, other
/// C0 controls, a raw NUL) into whatever reads this later.
fn validate_report_details(raw: &str) -> AppResult<String> {
    let trimmed = raw.trim();
    if trimmed.chars().count() > REPORT_DETAILS_MAX_CHARS {
        return Err(AppError::validation("details is too long"));
    }
    if trimmed
        .chars()
        .any(|c| c.is_control() && c != '\n' && c != '\t')
    {
        return Err(AppError::validation(
            "details has characters that aren't allowed",
        ));
    }
    Ok(trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn details_trims_and_accepts_normal_text() {
        assert_eq!(
            validate_report_details("  said something rude  ").unwrap(),
            "said something rude"
        );
    }

    #[test]
    fn details_rejects_over_the_length_limit() {
        let long = "a".repeat(REPORT_DETAILS_MAX_CHARS + 1);
        assert!(validate_report_details(&long).is_err());
    }

    #[test]
    fn details_allows_newline_and_tab() {
        assert!(validate_report_details("line one\nline two\tindented").is_ok());
    }

    #[test]
    fn details_rejects_other_control_characters() {
        assert!(validate_report_details("hi\0there").is_err());
        assert!(validate_report_details("hi\rthere").is_err());
    }
}
