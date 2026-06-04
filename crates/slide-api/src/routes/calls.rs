//! Call control plane: create / accept / decline / leave / history.
//!
//! This owns the *control* path only — room allocation, participant state, and
//! signaling fan-out. Media (SDP/ICE/RTP) happens on the SFU node the client
//! reaches via `sfuUrl` + `joinToken`.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use slide_core::{
    error::{AppError, AppResult},
    models::{Call, CallParticipant, CallType},
    turn::IceServer,
};

use crate::{auth::AuthUser, sfu_client, state::AppState};

// ── Views ────────────────────────────────────────────────────────────────────

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ParticipantView {
    user_id: Uuid,
    state: String,
    joined_at: Option<DateTime<Utc>>,
    left_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CallView {
    id: Uuid,
    room_id: String,
    sfu_node_id: String,
    #[serde(rename = "type")]
    call_type: CallType,
    created_by: Uuid,
    status: String,
    started_at: Option<DateTime<Utc>>,
    ended_at: Option<DateTime<Utc>>,
    created_at: DateTime<Utc>,
    participants: Vec<ParticipantView>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JoinResponse {
    call: CallView,
    join_token: String,
    sfu_url: String,
    ice_servers: Vec<IceServer>,
}

fn participant_state_str(s: &slide_core::models::ParticipantState) -> String {
    serde_json::to_value(s)
        .ok()
        .and_then(|v| v.as_str().map(|s| s.to_string()))
        .unwrap_or_default()
}

fn call_status_str(s: &slide_core::models::CallStatus) -> String {
    serde_json::to_value(s)
        .ok()
        .and_then(|v| v.as_str().map(|s| s.to_string()))
        .unwrap_or_default()
}

async fn load_call_view(state: &AppState, call_id: Uuid) -> AppResult<CallView> {
    let call: Call = sqlx::query_as("SELECT * FROM calls WHERE id = $1")
        .bind(call_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;

    let parts: Vec<CallParticipant> =
        sqlx::query_as("SELECT * FROM call_participants WHERE call_id = $1")
            .bind(call_id)
            .fetch_all(&state.db)
            .await?;

    Ok(CallView {
        id: call.id,
        room_id: call.room_id,
        sfu_node_id: call.sfu_node_id,
        call_type: call.call_type,
        created_by: call.created_by,
        status: call_status_str(&call.status),
        started_at: call.started_at,
        ended_at: call.ended_at,
        created_at: call.created_at,
        participants: parts
            .into_iter()
            .map(|p| ParticipantView {
                user_id: p.user_id,
                state: participant_state_str(&p.state),
                joined_at: p.joined_at,
                left_at: p.left_at,
            })
            .collect(),
    })
}

async fn participant_ids(state: &AppState, call_id: Uuid) -> AppResult<Vec<Uuid>> {
    let rows: Vec<(Uuid,)> =
        sqlx::query_as("SELECT user_id FROM call_participants WHERE call_id = $1")
            .bind(call_id)
            .fetch_all(&state.db)
            .await?;
    Ok(rows.into_iter().map(|(id,)| id).collect())
}

// ── POST /calls ───────────────────────────────────────────────────────────────

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateCallBody {
    #[serde(rename = "type")]
    pub call_type: CallType,
    pub participant_user_ids: Vec<Uuid>,
}

pub async fn create_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<CreateCallBody>,
) -> AppResult<Json<JoinResponse>> {
    // Validate participants.
    let mut callees: Vec<Uuid> = body
        .participant_user_ids
        .into_iter()
        .filter(|id| *id != uid)
        .collect();
    callees.sort();
    callees.dedup();

    if callees.is_empty() {
        return Err(AppError::bad_request("at least one participant required"));
    }
    if matches!(body.call_type, CallType::OneToOne) && callees.len() != 1 {
        return Err(AppError::bad_request(
            "one_to_one needs exactly one participant",
        ));
    }

    // Ensure all callees exist.
    let found: Vec<(Uuid,)> = sqlx::query_as("SELECT id FROM users WHERE id = ANY($1)")
        .bind(&callees)
        .fetch_all(&state.db)
        .await?;
    if found.len() != callees.len() {
        return Err(AppError::bad_request("unknown participant"));
    }

    let call_id = Uuid::new_v4();
    let alloc = sfu_client::allocate_room(&state, call_id);

    sqlx::query(
        "INSERT INTO calls (id, room_id, sfu_node_id, type, created_by, status)
         VALUES ($1, $2, $3, $4, $5, 'ringing')",
    )
    .bind(call_id)
    .bind(&alloc.room_id)
    .bind(&alloc.sfu_node_id)
    .bind(body.call_type)
    .bind(uid)
    .execute(&state.db)
    .await?;

    // Creator joins immediately; callees are ringing.
    sqlx::query(
        "INSERT INTO call_participants (call_id, user_id, state, joined_at)
         VALUES ($1, $2, 'joined', now())",
    )
    .bind(call_id)
    .bind(uid)
    .execute(&state.db)
    .await?;

    for c in &callees {
        sqlx::query(
            "INSERT INTO call_participants (call_id, user_id, state) VALUES ($1, $2, 'ringing')",
        )
        .bind(call_id)
        .bind(c)
        .execute(&state.db)
        .await?;
    }

    let view = load_call_view(&state, call_id).await?;
    let join_token =
        sfu_client::mint_join_token(&state, uid, call_id, &alloc.room_id, &alloc.sfu_node_id)?;
    let ice = sfu_client::ice_servers(&state, uid);

    let caller: Option<(Option<String>, String)> =
        sqlx::query_as("SELECT display_name, phone FROM users WHERE id = $1")
            .bind(uid)
            .fetch_optional(&state.db)
            .await?;
    let from_name = caller
        .as_ref()
        .and_then(|(name, _)| name.as_ref())
        .filter(|name| !name.trim().is_empty())
        .cloned()
        .or_else(|| caller.as_ref().map(|(_, phone)| phone.clone()))
        .unwrap_or_else(|| "Slide".to_string());

    // Ring the callees over the signaling socket (push fallback when offline).
    let event = json!({
        "type": "incoming_call",
        "callId": call_id,
        "callType": view.call_type,
        "fromUserId": uid,
        "fromName": from_name,
        "call": &view,
    });
    for c in &callees {
        let delivered = state.hub.publish(*c, event.clone()).await;
        if delivered == 0 {
            // Callee has no live socket → fall back to a real push so a closed
            // or backgrounded app still rings.
            tracing::info!(callee = %c, "callee offline — sending push notification");
            let push_payload = crate::push::IncomingPush {
                kind: "incoming_call".to_string(),
                call_id: Some(call_id),
                call_type: serde_json::to_value(view.call_type)
                    .ok()
                    .and_then(|v| v.as_str().map(str::to_string)),
                from_user_id: uid,
                from_name: from_name.clone(),
                knock: false,
            };
            state.push.notify_incoming(&state.db, *c, &push_payload).await;
        }
    }

    Ok(Json(JoinResponse {
        call: view,
        join_token,
        sfu_url: alloc.sfu_url,
        ice_servers: ice,
    }))
}

// ── helpers to ensure the caller belongs to the call ──────────────────────────

async fn require_participant(state: &AppState, call_id: Uuid, uid: Uuid) -> AppResult<Call> {
    let call: Call = sqlx::query_as("SELECT * FROM calls WHERE id = $1")
        .bind(call_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;
    let is_part: Option<(Uuid,)> =
        sqlx::query_as("SELECT user_id FROM call_participants WHERE call_id = $1 AND user_id = $2")
            .bind(call_id)
            .bind(uid)
            .fetch_optional(&state.db)
            .await?;
    if is_part.is_none() {
        return Err(AppError::Forbidden);
    }
    Ok(call)
}

// ── POST /calls/:id/accept ────────────────────────────────────────────────────

pub async fn accept_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(call_id): Path<Uuid>,
) -> AppResult<Json<JoinResponse>> {
    let call = require_participant(&state, call_id, uid).await?;
    if matches!(call.status, slide_core::models::CallStatus::Ended) {
        return Err(AppError::conflict("call already ended"));
    }

    sqlx::query(
        "UPDATE call_participants SET state = 'joined', joined_at = COALESCE(joined_at, now())
         WHERE call_id = $1 AND user_id = $2",
    )
    .bind(call_id)
    .bind(uid)
    .execute(&state.db)
    .await?;

    sqlx::query(
        "UPDATE calls SET status = 'active', started_at = COALESCE(started_at, now())
         WHERE id = $1 AND status <> 'ended'",
    )
    .bind(call_id)
    .execute(&state.db)
    .await?;

    let join_token =
        sfu_client::mint_join_token(&state, uid, call_id, &call.room_id, &call.sfu_node_id)?;
    let ice = sfu_client::ice_servers(&state, uid);
    let view = load_call_view(&state, call_id).await?;

    // Notify the others.
    let others: Vec<Uuid> = participant_ids(&state, call_id)
        .await?
        .into_iter()
        .filter(|id| *id != uid)
        .collect();
    let event = json!({ "type": "call_accepted", "callId": call_id, "userId": uid });
    state.hub.publish_many(&others, &event).await;

    Ok(Json(JoinResponse {
        call: view,
        join_token,
        sfu_url: format!("{}/ws?room={}", state.cfg.sfu_public_url, call.room_id),
        ice_servers: ice,
    }))
}

// ── POST /calls/:id/decline ───────────────────────────────────────────────────

pub async fn decline_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(call_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let call = require_participant(&state, call_id, uid).await?;

    sqlx::query(
        "UPDATE call_participants SET state = 'declined' WHERE call_id = $1 AND user_id = $2",
    )
    .bind(call_id)
    .bind(uid)
    .execute(&state.db)
    .await?;

    let others: Vec<Uuid> = participant_ids(&state, call_id)
        .await?
        .into_iter()
        .filter(|id| *id != uid)
        .collect();

    let mut ended = false;
    if matches!(call.call_type, CallType::OneToOne) {
        sqlx::query(
            "UPDATE calls SET status = 'declined', ended_at = now() WHERE id = $1 AND status <> 'ended'",
        )
        .bind(call_id)
        .execute(&state.db)
        .await?;
        ended = true;
    } else {
        // Group: end only if nobody is still ringing or joined.
        let active: Vec<(Uuid,)> = sqlx::query_as(
            "SELECT user_id FROM call_participants WHERE call_id = $1 AND state IN ('ringing','joined')",
        )
        .bind(call_id)
        .fetch_all(&state.db)
        .await?;
        if active.is_empty() {
            sqlx::query("UPDATE calls SET status = 'ended', ended_at = now() WHERE id = $1")
                .bind(call_id)
                .execute(&state.db)
                .await?;
            ended = true;
        }
    }

    let event = json!({ "type": "call_declined", "callId": call_id, "userId": uid });
    state.hub.publish_many(&others, &event).await;
    if ended {
        let end = json!({ "type": "call_ended", "callId": call_id });
        state.hub.publish_many(&others, &end).await;
    }

    Ok(StatusCode::NO_CONTENT)
}

// ── POST /calls/:id/leave ─────────────────────────────────────────────────────

pub async fn leave_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(call_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    require_participant(&state, call_id, uid).await?;

    sqlx::query(
        "UPDATE call_participants SET state = 'left', left_at = now()
         WHERE call_id = $1 AND user_id = $2",
    )
    .bind(call_id)
    .bind(uid)
    .execute(&state.db)
    .await?;

    let others: Vec<Uuid> = participant_ids(&state, call_id)
        .await?
        .into_iter()
        .filter(|id| *id != uid)
        .collect();
    let event = json!({ "type": "participant_left", "callId": call_id, "userId": uid });
    state.hub.publish_many(&others, &event).await;

    // End the call when no one is still joined.
    let still_joined: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT user_id FROM call_participants WHERE call_id = $1 AND state = 'joined'",
    )
    .bind(call_id)
    .fetch_all(&state.db)
    .await?;
    if still_joined.is_empty() {
        sqlx::query("UPDATE calls SET status = 'ended', ended_at = now() WHERE id = $1 AND status <> 'ended'")
            .bind(call_id)
            .execute(&state.db)
            .await?;
        let end = json!({ "type": "call_ended", "callId": call_id });
        state.hub.publish_many(&others, &end).await;
    }

    Ok(StatusCode::NO_CONTENT)
}

// ── GET /calls?cursor= ────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct HistoryQuery {
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryResponse {
    calls: Vec<CallView>,
    next_cursor: Option<String>,
}

pub async fn list_calls(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Query(q): Query<HistoryQuery>,
) -> AppResult<Json<HistoryResponse>> {
    let limit = q.limit.unwrap_or(30).clamp(1, 100);
    let cursor_ts: Option<DateTime<Utc>> = match q.cursor.as_deref() {
        Some(c) => Some(
            c.parse()
                .map_err(|_| AppError::bad_request("invalid cursor"))?,
        ),
        None => None,
    };

    // Calls the user participates in, newest first, keyset-paginated by created_at.
    let calls: Vec<Call> = sqlx::query_as(
        "SELECT c.* FROM calls c
           JOIN call_participants p ON p.call_id = c.id
          WHERE p.user_id = $1
            AND ($2::timestamptz IS NULL OR c.created_at < $2)
          ORDER BY c.created_at DESC
          LIMIT $3",
    )
    .bind(uid)
    .bind(cursor_ts)
    .bind(limit)
    .fetch_all(&state.db)
    .await?;

    let next_cursor = if calls.len() as i64 == limit {
        calls.last().map(|c| c.created_at.to_rfc3339())
    } else {
        None
    };

    let mut views = Vec::with_capacity(calls.len());
    for c in calls {
        views.push(load_call_view(&state, c.id).await?);
    }

    Ok(Json(HistoryResponse {
        calls: views,
        next_cursor,
    }))
}
