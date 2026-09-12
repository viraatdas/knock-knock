//! Lobby + the date lifecycle (SPEC.md section 1.6).
//!
//! Preconditions and pairing/expiry all live here; the actual pairing
//! decisions (compatibility, greedy pairing) live in [`crate::matcher`].
//! Responses are built with [`crate::views::date_session_for`] /
//! [`crate::views::public_profile`] / [`crate::views::match_summary`].
//!
//! Deviation from SPEC.md's literal wording, called out per the build task:
//! SPEC 1.6 says a lobby join/heartbeat with an open date already in progress
//! should 409 `date_in_progress` (including the date). This implementation
//! instead returns 200 `{"status":"matched","date":...}` in that case, same
//! as a fresh match — the client just presents the date either way, so an
//! error code buys nothing and this matches the literal task instructions for
//! this stage. There's no other consumer of `date_in_progress` anywhere else
//! in the spec (iOS section 2.3 already treats a "date_in_progress" response
//! from join identically to a normal match: "present the date").

use std::time::Duration;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use slide_core::{
    error::{AppError, AppResult},
    models::{DateRow, MatchRow, User, USER_COLUMNS},
};

use crate::{
    auth::AuthUser,
    matcher,
    session::SessionWindow,
    state::AppState,
    views::{self, DateSession},
};

async fn fetch_user(state: &AppState, uid: Uuid) -> AppResult<User> {
    let sql = format!("SELECT {USER_COLUMNS} FROM users WHERE id = $1");
    sqlx::query_as::<_, User>(&sql)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)
}

/// The caller's currently open date (`ended_at IS NULL`), if any. Shared by
/// `lobby_join`/`lobby_heartbeat`/`current_date`.
async fn open_date_for(state: &AppState, uid: Uuid) -> AppResult<Option<DateRow>> {
    let row: Option<DateRow> = sqlx::query_as(
        "SELECT * FROM dates
          WHERE (user_a = $1 OR user_b = $1) AND ended_at IS NULL
          ORDER BY started_at DESC
          LIMIT 1",
    )
    .bind(uid)
    .fetch_optional(&state.db)
    .await?;
    Ok(row)
}

async fn fetch_date_or_404(state: &AppState, date_id: Uuid) -> AppResult<DateRow> {
    sqlx::query_as("SELECT * FROM dates WHERE id = $1")
        .bind(date_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)
}

#[derive(Debug, Serialize)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum LobbyResponse {
    Waiting,
    Matched { date: Box<DateSession> },
}

/// POST /lobby/join. Preconditions, in order (an already-open date short-
/// circuits everything else, see the module doc comment): session open for
/// this user (409 `session_closed`), profile complete (422
/// `profile_incomplete`), location present (422 `location_required`). On
/// success, upserts the `lobby` row and runs one synchronous
/// `matcher::run_once` pass before responding.
pub async fn lobby_join(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<LobbyResponse>> {
    if let Some(existing) = open_date_for(&state, uid).await? {
        let session = views::date_session_for(&state, &existing, uid).await?;
        return Ok(Json(LobbyResponse::Matched {
            date: Box::new(session),
        }));
    }

    let user = views::self_or_unauthorized(fetch_user(&state, uid).await)?;
    let now = Utc::now();
    let window = SessionWindow::compute(&state.cfg, now, user.is_review_account);
    if !window.is_open {
        return Err(AppError::conflict_code(
            "session_closed",
            "the doors are closed for tonight",
        ));
    }
    if !views::profile_is_complete(&user) {
        return Err(AppError::validation_code(
            "profile_incomplete",
            "finish your profile before joining",
        ));
    }
    if user.lat.is_none() || user.lng.is_none() {
        return Err(AppError::validation_code(
            "location_required",
            "turn on location before joining",
        ));
    }

    sqlx::query(
        "INSERT INTO lobby (user_id, session_date, joined_at, heartbeat_at)
         VALUES ($1, $2, now(), now())
         ON CONFLICT (user_id)
         DO UPDATE SET session_date = EXCLUDED.session_date,
                       joined_at = now(),
                       heartbeat_at = now()",
    )
    .bind(uid)
    .bind(window.session_date)
    .execute(&state.db)
    .await?;

    if let Err(error) = matcher::run_once(&state).await {
        tracing::error!(%error, "matcher pass after lobby_join failed");
    }

    match open_date_for(&state, uid).await? {
        Some(row) => {
            let session = views::date_session_for(&state, &row, uid).await?;
            Ok(Json(LobbyResponse::Matched {
                date: Box::new(session),
            }))
        }
        None => Ok(Json(LobbyResponse::Waiting)),
    }
}

/// POST /lobby/heartbeat. Refreshes `heartbeat_at` for the caller's `lobby`
/// row (a no-op if they aren't in the lobby); if the caller already has an
/// open date, returns it as `matched` — the poll fallback for a missed
/// `date_matched` WS event. Called every 5s by the client. Does not re-check
/// the `lobby_join` preconditions: those were already satisfied at join time.
pub async fn lobby_heartbeat(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<LobbyResponse>> {
    sqlx::query("UPDATE lobby SET heartbeat_at = now() WHERE user_id = $1")
        .bind(uid)
        .execute(&state.db)
        .await?;

    match open_date_for(&state, uid).await? {
        Some(row) => {
            let session = views::date_session_for(&state, &row, uid).await?;
            Ok(Json(LobbyResponse::Matched {
                date: Box::new(session),
            }))
        }
        None => Ok(Json(LobbyResponse::Waiting)),
    }
}

/// DELETE /lobby. Removes the caller's `lobby` row, if any.
pub async fn lobby_leave(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<StatusCode> {
    sqlx::query("DELETE FROM lobby WHERE user_id = $1")
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CurrentDateResponse {
    pub date: Option<DateSession>,
}

/// GET /dates/current. The caller's open date (`ended_at IS NULL`), if any.
pub async fn current_date(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<CurrentDateResponse>> {
    let date = match open_date_for(&state, uid).await? {
        Some(row) => Some(views::date_session_for(&state, &row, uid).await?),
        None => None,
    };
    Ok(Json(CurrentDateResponse { date }))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodayDateEntry {
    pub id: Uuid,
    pub partner: crate::views::PublicProfile,
    pub started_at: chrono::DateTime<chrono::Utc>,
    pub ended_at: Option<chrono::DateTime<chrono::Utc>>,
    /// The caller's own decision only — the partner's decision is never
    /// exposed here.
    pub my_decision: Option<bool>,
    pub matched: bool,
}

/// GET /dates/today. Every date for the caller whose `session_date` is
/// today's local (`SESSION_TZ`) calendar date — deliberately *not*
/// `SessionWindow::compute(...).session_date`, which reports *tomorrow*'s
/// date once the window has closed for the night (see `session.rs`); this
/// recap is meant to keep showing tonight's dates right after 8 PM.
pub async fn today_dates(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<Vec<TodayDateEntry>>> {
    let today = Utc::now().with_timezone(&state.cfg.session_tz).date_naive();
    let rows: Vec<DateRow> = sqlx::query_as(
        "SELECT * FROM dates
          WHERE (user_a = $1 OR user_b = $1) AND session_date = $2
          ORDER BY started_at ASC",
    )
    .bind(uid)
    .bind(today)
    .fetch_all(&state.db)
    .await?;

    let mut entries = Vec::with_capacity(rows.len());
    for row in rows {
        let partner_id = if row.user_a == uid {
            row.user_b
        } else {
            row.user_a
        };
        let partner = views::public_profile(&state, uid, partner_id).await?;
        let my_decision = if row.user_a == uid {
            row.decision_a
        } else {
            row.decision_b
        };
        let matched: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM matches WHERE date_id = $1)")
                .bind(row.id)
                .fetch_one(&state.db)
                .await?;
        entries.push(TodayDateEntry {
            id: row.id,
            partner,
            started_at: row.started_at,
            ended_at: row.ended_at,
            my_decision,
            matched,
        });
    }
    Ok(Json(entries))
}

/// POST /dates/:id/leave. Ends the date exactly once (`end_reason='left'`)
/// via `UPDATE ... WHERE ended_at IS NULL RETURNING`, publishing `date_ended`
/// to both participants; idempotent (a second call on an already-ended date
/// is a no-op).
pub async fn leave_date(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(date_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let row = fetch_date_or_404(&state, date_id).await?;
    if row.user_a != uid && row.user_b != uid {
        return Err(AppError::NotFound);
    }

    let ended: Option<DateRow> = sqlx::query_as(
        "UPDATE dates SET ended_at = now(), end_reason = 'left'
          WHERE id = $1 AND ended_at IS NULL
          RETURNING *",
    )
    .bind(date_id)
    .fetch_optional(&state.db)
    .await?;

    if let Some(ended) = ended {
        let event = json!({ "type": "date_ended", "dateId": ended.id, "reason": "left" });
        state
            .hub
            .publish_many(&[ended.user_a, ended.user_b], &event)
            .await;
    }
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DecisionBody {
    pub explore: bool,
}

#[derive(Debug, Serialize)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum DecisionResponse {
    Waiting,
    Matched {
        #[serde(rename = "match")]
        the_match: Box<crate::views::MatchSummary>,
    },
    Passed,
}

/// POST /dates/:id/decision. Allowed only after the date has ended.
/// Idempotent: resubmitting the same answer returns the current status
/// (including re-returning `matched` without re-publishing/re-pushing if the
/// match already exists); a changed answer is rejected with 409
/// `decision_changed`. On mutual `true`: lands the `matches` row
/// (`user_a < user_b`) via `INSERT ... ON CONFLICT DO NOTHING RETURNING *`,
/// falling back to a resurrecting `UPDATE` when the pair already has a dead
/// (unmatched) row from a prior match — see the insert-or-resurrect comment
/// below for why the outcome of those statements, not a separate SELECT, is
/// what decides `newly_created`. Publishes `match_made` to both and sends an
/// APNs alert to whichever side answered first, exactly once regardless of a
/// retried request. A `false` is never revealed to the other side — that side
/// just stays `waiting`.
pub async fn decide_date(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(date_id): Path<Uuid>,
    Json(body): Json<DecisionBody>,
) -> AppResult<Json<DecisionResponse>> {
    let row = fetch_date_or_404(&state, date_id).await?;
    let is_a = if row.user_a == uid {
        true
    } else if row.user_b == uid {
        false
    } else {
        return Err(AppError::NotFound);
    };

    if row.ended_at.is_none() {
        return Err(AppError::conflict_code(
            "date_not_ended",
            "the date hasn't ended yet",
        ));
    }

    // Atomically record this side's decision only if it isn't already set —
    // both branches touch the same row, so concurrent decisions from the two
    // sides serialize on Postgres's row lock rather than racing.
    let updated: DateRow = if is_a {
        sqlx::query_as(
            "UPDATE dates SET
                decision_a = COALESCE(decision_a, $2),
                decided_a_at = COALESCE(decided_a_at, now())
              WHERE id = $1
              RETURNING *",
        )
        .bind(date_id)
        .bind(body.explore)
        .fetch_one(&state.db)
        .await?
    } else {
        sqlx::query_as(
            "UPDATE dates SET
                decision_b = COALESCE(decision_b, $2),
                decided_b_at = COALESCE(decided_b_at, now())
              WHERE id = $1
              RETURNING *",
        )
        .bind(date_id)
        .bind(body.explore)
        .fetch_one(&state.db)
        .await?
    };

    let my_decision = if is_a {
        updated.decision_a
    } else {
        updated.decision_b
    };
    if my_decision != Some(body.explore) {
        return Err(AppError::conflict_code(
            "decision_changed",
            "you already answered differently",
        ));
    }

    if !body.explore {
        return Ok(Json(DecisionResponse::Passed));
    }

    let other_decision = if is_a {
        updated.decision_b
    } else {
        updated.decision_a
    };
    if other_decision != Some(true) {
        return Ok(Json(DecisionResponse::Waiting));
    }

    let (ua, ub) = if updated.user_a < updated.user_b {
        (updated.user_a, updated.user_b)
    } else {
        (updated.user_b, updated.user_a)
    };

    // Insert-or-resurrect: `newly_created` comes from whichever statement's
    // own `RETURNING` actually produced a row, never from a separate
    // check-then-act SELECT. That makes "exactly one write wins" and
    // "exactly one publish/push" the same atomic fact, which closes two bugs
    // a preliminary SELECT had: (1) two concurrent decide calls (e.g. a
    // client retry on a flaky connection) could both see no existing row,
    // both take the "create" branch, and both fire `match_made`/the alert
    // even though `ON CONFLICT DO NOTHING` correctly left only one row; (2)
    // re-matching a pair after an unmatch found the old dead row and treated
    // it as already-matched — telling both sides "it's a match" while the row
    // stayed `unmatched_at IS NOT NULL`, invisible to `GET /matches` and
    // `/matches/:id/*` forever.
    let inserted: Option<MatchRow> = sqlx::query_as(
        "INSERT INTO matches (user_a, user_b, date_id) VALUES ($1, $2, $3)
          ON CONFLICT (user_a, user_b) DO NOTHING
          RETURNING *",
    )
    .bind(ua)
    .bind(ub)
    .bind(updated.id)
    .fetch_optional(&state.db)
    .await?;

    let (match_row, newly_created) = match inserted {
        Some(m) => (m, true),
        None => {
            // The pair already has a row (brand new pairs always take the
            // INSERT branch above). If it's dead, revive it — same
            // "RETURNING decides newly_created" atomicity: only one of two
            // concurrent resurrect attempts can flip `unmatched_at` from
            // non-null to null, so only one gets a row back.
            let resurrected: Option<MatchRow> = sqlx::query_as(
                "UPDATE matches
                    SET unmatched_at = NULL, unmatched_by = NULL, date_id = $3
                  WHERE user_a = $1 AND user_b = $2 AND unmatched_at IS NOT NULL
                  RETURNING *",
            )
            .bind(ua)
            .bind(ub)
            .bind(updated.id)
            .fetch_optional(&state.db)
            .await?;

            match resurrected {
                Some(m) => (m, true),
                None => {
                    // Neither statement produced a row: the match is already
                    // active. This is the resubmit-the-same-answer / retried-
                    // request case — return it without re-publishing/re-
                    // pushing.
                    let m: MatchRow =
                        sqlx::query_as("SELECT * FROM matches WHERE user_a = $1 AND user_b = $2")
                            .bind(ua)
                            .bind(ub)
                            .fetch_one(&state.db)
                            .await?;
                    (m, false)
                }
            }
        }
    };

    if newly_created {
        let summary_a = views::match_summary(&state, &match_row, match_row.user_a).await?;
        let summary_b = views::match_summary(&state, &match_row, match_row.user_b).await?;
        state
            .hub
            .publish(
                match_row.user_a,
                json!({ "type": "match_made", "match": summary_a }),
            )
            .await;
        state
            .hub
            .publish(
                match_row.user_b,
                json!({ "type": "match_made", "match": summary_b }),
            )
            .await;

        // Whoever's decided_at is earlier answered first and has been
        // waiting without knowing; the current request is always the side
        // that just completed the mutual yes, so the alert always goes to
        // the *other* person.
        let (first_id, second_id) = if updated.decided_a_at <= updated.decided_b_at {
            (updated.user_a, updated.user_b)
        } else {
            (updated.user_b, updated.user_a)
        };
        let second_profile = views::public_profile(&state, first_id, second_id).await?;
        let mut data = serde_json::Map::new();
        data.insert("type".to_string(), json!("match_made"));
        data.insert("matchId".to_string(), json!(match_row.id));
        state
            .push
            .notify_alert(
                &state.db,
                first_id,
                "It's a match",
                &format!(
                    "You and {} both want to keep talking.",
                    second_profile.display_name
                ),
                Some(&match_row.id.to_string()),
                None,
                3600,
                Some(data),
            )
            .await;
    }

    let my_summary = views::match_summary(&state, &match_row, uid).await?;
    Ok(Json(DecisionResponse::Matched {
        the_match: Box::new(my_summary),
    }))
}

/// Background task: dates with `ends_at <= now()` and `ended_at IS NULL` get
/// `ended_at = now(), end_reason = 'timeout'`, publishing `date_ended
/// { "dateId", "reason": "timeout" }` to both participants. Spawned once from
/// `main`.
pub async fn run_date_expirer(state: AppState) {
    let mut ticker = tokio::time::interval(Duration::from_secs(1));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        ticker.tick().await;
        if let Err(error) = expire_due_dates(&state).await {
            tracing::error!(%error, "date expirer pass failed");
        }
    }
}

async fn expire_due_dates(state: &AppState) -> AppResult<()> {
    let rows: Vec<DateRow> = sqlx::query_as(
        "UPDATE dates SET ended_at = now(), end_reason = 'timeout'
          WHERE ends_at <= now() AND ended_at IS NULL
          RETURNING *",
    )
    .fetch_all(&state.db)
    .await?;

    for row in rows {
        let event = json!({ "type": "date_ended", "dateId": row.id, "reason": "timeout" });
        state
            .hub
            .publish_many(&[row.user_a, row.user_b], &event)
            .await;
    }
    Ok(())
}
