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
    models::{Call, CallStatus, CallType, ParticipantState},
    turn::IceServer,
};

use crate::{auth::AuthUser, sfu_client, state::AppState};

// ── Views ────────────────────────────────────────────────────────────────────

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ParticipantView {
    user_id: Uuid,
    state: String,
    joined_at: Option<DateTime<Utc>>,
    left_at: Option<DateTime<Utc>>,
    display_name: Option<String>,
    phone: Option<String>,
    avatar_url: Option<String>,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct CallView {
    id: Uuid,
    room_id: String,
    sfu_node_id: String,
    #[serde(rename = "type")]
    call_type: CallType,
    created_by: Uuid,
    status: String,
    video_enabled: bool,
    ring_style: String,
    started_at: Option<DateTime<Utc>>,
    ended_at: Option<DateTime<Utc>>,
    created_at: DateTime<Utc>,
    participants: Vec<ParticipantView>,
}

#[derive(sqlx::FromRow)]
struct ParticipantRow {
    user_id: Uuid,
    state: ParticipantState,
    joined_at: Option<DateTime<Utc>>,
    left_at: Option<DateTime<Utc>>,
    display_name: Option<String>,
    phone: Option<String>,
    avatar_url: Option<String>,
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

    let parts: Vec<ParticipantRow> = sqlx::query_as(
        "SELECT p.user_id, p.state, p.joined_at, p.left_at,
                    u.display_name, u.phone, u.avatar_url
               FROM call_participants p
               LEFT JOIN users u ON u.id = p.user_id
              WHERE p.call_id = $1",
    )
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
        video_enabled: call.video_enabled,
        ring_style: call.ring_style,
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
                display_name: p.display_name,
                phone: p.phone,
                avatar_url: p.avatar_url,
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

async fn call_display_name(state: &AppState, user_id: Uuid) -> AppResult<String> {
    let caller: Option<(Option<String>, String)> =
        sqlx::query_as("SELECT display_name, phone FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?;
    Ok(caller
        .as_ref()
        .and_then(|(name, _)| name.as_ref())
        .map(|name| name.trim())
        .filter(|name| !name.is_empty())
        .map(str::to_string)
        .or_else(|| caller.as_ref().map(|(_, phone)| phone.clone()))
        .unwrap_or_else(|| "Slide".to_string()))
}

// ── POST /calls ───────────────────────────────────────────────────────────────

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateCallBody {
    #[serde(rename = "type")]
    pub call_type: CallType,
    pub participant_user_ids: Vec<Uuid>,
    #[serde(default = "default_video_enabled")]
    pub video_enabled: bool,
    #[serde(default = "default_ring_style")]
    pub ring_style: String,
}

fn default_video_enabled() -> bool {
    true
}

fn default_ring_style() -> String {
    "call".to_string()
}

pub async fn create_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<CreateCallBody>,
) -> AppResult<Json<JoinResponse>> {
    let ring_style = match body.ring_style.as_str() {
        "call" | "knock" => body.ring_style.clone(),
        _ => return Err(AppError::bad_request("ringStyle must be call or knock")),
    };
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
        "INSERT INTO calls (id, room_id, sfu_node_id, type, created_by, status, video_enabled, ring_style)
         VALUES ($1, $2, $3, $4, $5, 'ringing', $6, $7)",
    )
    .bind(call_id)
    .bind(&alloc.room_id)
    .bind(&alloc.sfu_node_id)
    .bind(body.call_type)
    .bind(uid)
    .bind(body.video_enabled)
    .bind(&ring_style)
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
    let ice = sfu_client::ice_servers(&state, uid);

    let from_name = call_display_name(&state, uid).await?;

    let (sfu_url, join_token) = sfu_client::media_join(
        &state,
        uid,
        Some(&from_name),
        call_id,
        &alloc.room_id,
        &alloc.sfu_node_id,
    )?;

    let ring_state = state.clone();
    let ring_view = view.clone();
    let ring_callees = callees.clone();
    tokio::spawn(async move {
        ring_callees_for_call(ring_state, ring_callees, uid, from_name, ring_view).await;
    });

    Ok(Json(JoinResponse {
        call: view,
        join_token,
        sfu_url,
        ice_servers: ice,
    }))
}

async fn ring_callees_for_call(
    state: AppState,
    callees: Vec<Uuid>,
    caller_id: Uuid,
    from_name: String,
    view: CallView,
) {
    let is_knock = view.ring_style == "knock";
    let event = json!({
        "type": "incoming_call",
        "callId": view.id,
        "callType": view.call_type,
        "videoEnabled": view.video_enabled,
        "ringStyle": &view.ring_style,
        "knock": is_knock,
        "fromUserId": caller_id,
        "fromName": &from_name,
        "call": &view,
    });

    for callee in &callees {
        let delivered = state.hub.publish(*callee, event.clone()).await;
        if delivered == 0 {
            // Callee has no live socket, so fall back to a real push so a closed
            // or backgrounded app still rings.
            tracing::info!(callee = %callee, "callee offline - sending push notification");
            let push_payload = crate::push::IncomingPush {
                kind: "incoming_call".to_string(),
                call_id: Some(view.id),
                call_type: serde_json::to_value(view.call_type)
                    .ok()
                    .and_then(|v| v.as_str().map(str::to_string)),
                from_user_id: caller_id,
                from_name: from_name.clone(),
                video_enabled: view.video_enabled,
                ring_style: view.ring_style.clone(),
                knock: is_knock,
            };
            state
                .push
                .notify_incoming(&state.db, *callee, &push_payload)
                .await;
        }
    }
}

fn spawn_call_closed_push(state: AppState, recipients: Vec<Uuid>, call_id: Uuid, actor_id: Uuid) {
    tokio::spawn(async move {
        let payload = crate::push::IncomingPush {
            kind: "call_ended".to_string(),
            call_id: Some(call_id),
            call_type: None,
            from_user_id: actor_id,
            from_name: "Slide".to_string(),
            video_enabled: true,
            ring_style: "call".to_string(),
            knock: false,
        };
        for recipient in recipients {
            state
                .push
                .notify_incoming(&state.db, recipient, &payload)
                .await;
        }
    });
}

/// Fire-and-forget visible "missed knock" alert to the callee(s) when a
/// ringing 1:1 call ends unanswered. Mirrors `spawn_call_closed_push`.
fn spawn_missed_call_alert(state: AppState, recipients: Vec<Uuid>) {
    tokio::spawn(async move {
        for recipient in recipients {
            state
                .push
                .notify_alert(
                    &state.db,
                    recipient,
                    "You missed a knock",
                    "Open Knock Knock to see who it was",
                    Some("missed"),
                    None,
                )
                .await;
        }
    });
}

// ── helpers to ensure the caller belongs to the call ──────────────────────────

struct ParticipantAccess {
    call: Call,
    participant_state: ParticipantState,
}

async fn require_participant(
    state: &AppState,
    call_id: Uuid,
    uid: Uuid,
) -> AppResult<ParticipantAccess> {
    let call: Call = sqlx::query_as("SELECT * FROM calls WHERE id = $1")
        .bind(call_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;
    let participant: Option<(ParticipantState,)> =
        sqlx::query_as("SELECT state FROM call_participants WHERE call_id = $1 AND user_id = $2")
            .bind(call_id)
            .bind(uid)
            .fetch_optional(&state.db)
            .await?;
    let participant_state = participant.ok_or(AppError::Forbidden)?.0;
    Ok(ParticipantAccess {
        call,
        participant_state,
    })
}

// ── POST /calls/:id/accept ────────────────────────────────────────────────────

pub async fn accept_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(call_id): Path<Uuid>,
) -> AppResult<Json<JoinResponse>> {
    let access = require_participant(&state, call_id, uid).await?;
    let call = access.call;
    if matches!(
        call.status,
        CallStatus::Ended | CallStatus::Missed | CallStatus::Declined
    ) {
        return Err(AppError::conflict("call already ended"));
    }
    let can_accept = matches!(access.participant_state, ParticipantState::Ringing)
        || (matches!(access.participant_state, ParticipantState::Joined)
            && matches!(call.status, CallStatus::Active));
    if !can_accept {
        return Err(AppError::conflict("call is not ringing"));
    }

    let updated = sqlx::query(
        "UPDATE calls SET status = 'active', started_at = COALESCE(started_at, now())
         WHERE id = $1 AND status IN ('ringing', 'active')",
    )
    .bind(call_id)
    .execute(&state.db)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::conflict("call already ended"));
    }

    let participant_updated = sqlx::query(
        "UPDATE call_participants SET state = 'joined', joined_at = COALESCE(joined_at, now())
         WHERE call_id = $1 AND user_id = $2 AND state IN ('ringing', 'joined')",
    )
    .bind(call_id)
    .bind(uid)
    .execute(&state.db)
    .await?;
    if participant_updated.rows_affected() == 0 {
        return Err(AppError::conflict("call is not ringing"));
    }

    let display_name = call_display_name(&state, uid).await?;
    let (sfu_url, join_token) = sfu_client::media_join(
        &state,
        uid,
        Some(&display_name),
        call_id,
        &call.room_id,
        &call.sfu_node_id,
    )?;
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
        sfu_url,
        ice_servers: ice,
    }))
}

// ── POST /calls/:id/decline ───────────────────────────────────────────────────

pub async fn decline_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(call_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let access = require_participant(&state, call_id, uid).await?;
    let call = access.call;
    if matches!(
        call.status,
        CallStatus::Ended | CallStatus::Missed | CallStatus::Declined
    ) {
        return Ok(StatusCode::NO_CONTENT);
    }
    if !matches!(access.participant_state, ParticipantState::Ringing) {
        return Ok(StatusCode::NO_CONTENT);
    }

    if matches!(call.call_type, CallType::OneToOne) {
        let updated = sqlx::query(
            "UPDATE calls SET status = 'declined', ended_at = now()
              WHERE id = $1 AND status = 'ringing'",
        )
        .bind(call_id)
        .execute(&state.db)
        .await?;
        if updated.rows_affected() == 0 {
            return Ok(StatusCode::NO_CONTENT);
        }

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
        let event = json!({ "type": "call_declined", "callId": call_id, "userId": uid });
        state.hub.publish_many(&others, &event).await;
        let end = json!({ "type": "call_ended", "callId": call_id });
        state.hub.publish_many(&others, &end).await;
        spawn_call_closed_push(state.clone(), others, call_id, uid);
        return Ok(StatusCode::NO_CONTENT);
    }

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
    // Group: end only if nobody is still ringing or joined.
    let active: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT user_id FROM call_participants WHERE call_id = $1 AND state IN ('ringing','joined')",
    )
    .bind(call_id)
    .fetch_all(&state.db)
    .await?;
    if active.is_empty() {
        sqlx::query("UPDATE calls SET status = 'ended', ended_at = now() WHERE id = $1 AND status NOT IN ('ended', 'missed', 'declined')")
            .bind(call_id)
            .execute(&state.db)
            .await?;
        ended = true;
    }

    let event = json!({ "type": "call_declined", "callId": call_id, "userId": uid });
    state.hub.publish_many(&others, &event).await;
    if ended {
        let end = json!({ "type": "call_ended", "callId": call_id });
        state.hub.publish_many(&others, &end).await;
        spawn_call_closed_push(state.clone(), others, call_id, uid);
    }

    Ok(StatusCode::NO_CONTENT)
}

// ── POST /calls/:id/leave ─────────────────────────────────────────────────────

pub async fn leave_call(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Path(call_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let access = require_participant(&state, call_id, uid).await?;
    let call = access.call;
    if matches!(
        call.status,
        CallStatus::Ended | CallStatus::Missed | CallStatus::Declined
    ) {
        return Ok(StatusCode::NO_CONTENT);
    }

    let others: Vec<Uuid> = participant_ids(&state, call_id)
        .await?
        .into_iter()
        .filter(|id| *id != uid)
        .collect();

    if matches!(call.call_type, CallType::OneToOne) {
        if matches!(access.participant_state, ParticipantState::Ringing) {
            let updated = sqlx::query(
                "UPDATE calls SET status = 'declined', ended_at = now()
                  WHERE id = $1 AND status = 'ringing'",
            )
            .bind(call_id)
            .execute(&state.db)
            .await?;
            if updated.rows_affected() == 0 {
                return Ok(StatusCode::NO_CONTENT);
            }
            sqlx::query(
                "UPDATE call_participants SET state = 'declined'
                  WHERE call_id = $1 AND user_id = $2 AND state = 'ringing'",
            )
            .bind(call_id)
            .bind(uid)
            .execute(&state.db)
            .await?;
            let event = json!({ "type": "call_declined", "callId": call_id, "userId": uid });
            state.hub.publish_many(&others, &event).await;
            let end = json!({ "type": "call_ended", "callId": call_id });
            state.hub.publish_many(&others, &end).await;
            spawn_call_closed_push(state.clone(), others, call_id, uid);
            return Ok(StatusCode::NO_CONTENT);
        }

        sqlx::query(
            "UPDATE call_participants SET state = 'left', left_at = now()
             WHERE call_id = $1 AND user_id = $2",
        )
        .bind(call_id)
        .bind(uid)
        .execute(&state.db)
        .await?;
        sqlx::query(
            "UPDATE call_participants
                SET state = 'left', left_at = COALESCE(left_at, now())
              WHERE call_id = $1 AND state = 'ringing'",
        )
        .bind(call_id)
        .execute(&state.db)
        .await?;
        let final_status: Option<(CallStatus,)> = sqlx::query_as(
            "UPDATE calls
                SET status = CASE
                        WHEN status = 'ringing' THEN 'missed'::call_status
                        ELSE 'ended'::call_status
                    END,
                    ended_at = now()
              WHERE id = $1 AND status NOT IN ('ended', 'missed', 'declined')
              RETURNING status",
        )
        .bind(call_id)
        .fetch_optional(&state.db)
        .await?;
        let event = json!({ "type": "participant_left", "callId": call_id, "userId": uid });
        state.hub.publish_many(&others, &event).await;
        let end = json!({ "type": "call_ended", "callId": call_id });
        state.hub.publish_many(&others, &end).await;
        // Caller hung up before the callee answered → tell the callee they
        // missed it with a visible alert push (the VoIP ring alone vanishes).
        if matches!(final_status, Some((CallStatus::Missed,))) {
            spawn_missed_call_alert(state.clone(), others.clone());
        }
        spawn_call_closed_push(state.clone(), others, call_id, uid);
        return Ok(StatusCode::NO_CONTENT);
    }

    sqlx::query(
        "UPDATE call_participants SET state = 'left', left_at = now()
         WHERE call_id = $1 AND user_id = $2",
    )
    .bind(call_id)
    .bind(uid)
    .execute(&state.db)
    .await?;

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
        sqlx::query("UPDATE calls SET status = 'ended', ended_at = now() WHERE id = $1 AND status NOT IN ('ended', 'missed', 'declined')")
            .bind(call_id)
            .execute(&state.db)
            .await?;
        let end = json!({ "type": "call_ended", "callId": call_id });
        state.hub.publish_many(&others, &end).await;
        spawn_call_closed_push(state.clone(), others, call_id, uid);
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
