//! App-signaling WebSocket: `GET /v1/ws?token=<accessToken>`.
//!
//! Carries call lifecycle + presence events to the client. The token is passed
//! as a query parameter because browsers/native sockets can't easily set the
//! Authorization header on the upgrade request. On connect we mark the user
//! present; on disconnect, absent.

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    response::Response,
};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{auth, state::AppState};

#[derive(Deserialize)]
pub struct WsQuery {
    pub token: String,
}

pub async fn ws_handler(
    State(state): State<AppState>,
    Query(q): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Response {
    // Authenticate before upgrading.
    let uid = match auth::verify_query_token(&state, &q.token) {
        Ok(uid) => uid,
        Err(_) => {
            return axum::http::StatusCode::UNAUTHORIZED.into_response_via();
        }
    };
    ws.on_upgrade(move |socket| handle_socket(socket, state, uid))
}

// Tiny helper to turn a status into a Response without pulling in IntoResponse
// at the call site above (keeps the match arms tidy).
trait IntoResponseExt {
    fn into_response_via(self) -> Response;
}
impl IntoResponseExt for axum::http::StatusCode {
    fn into_response_via(self) -> Response {
        use axum::response::IntoResponse;
        self.into_response()
    }
}

async fn signaling_display_name(state: &AppState, uid: Uuid) -> String {
    let user: Option<(Option<String>, String)> =
        match sqlx::query_as("SELECT display_name, phone FROM users WHERE id = $1")
            .bind(uid)
            .fetch_optional(&state.db)
            .await
        {
            Ok(user) => user,
            Err(err) => {
                tracing::warn!(user = %uid, error = %err, "ws: failed to load display name");
                None
            }
        };
    user.as_ref()
        .and_then(|(name, _)| name.as_ref())
        .map(|name| name.trim())
        .filter(|name| !name.is_empty())
        .map(str::to_string)
        .or_else(|| user.as_ref().map(|(_, phone)| phone.clone()))
        .unwrap_or_else(|| "Slide".to_string())
}

async fn handle_socket(socket: WebSocket, state: AppState, uid: Uuid) {
    use futures::{SinkExt, StreamExt};

    let (mut sender, mut receiver) = socket.split();
    let (conn_id, mut rx) = state.hub.connect(uid).await;

    // Announce presence to nobody in particular yet; mark last_seen.
    let _ = sqlx::query("UPDATE users SET last_seen_at = now() WHERE id = $1")
        .bind(uid)
        .execute(&state.db)
        .await;

    let from_name = signaling_display_name(&state, uid).await;

    // Outbound pump: hub events → socket.
    let send_task = tokio::spawn(async move {
        while let Some(evt) = rx.recv().await {
            let txt = evt.to_string();
            if sender.send(Message::Text(txt.into())).await.is_err() {
                break;
            }
        }
    });

    // Inbound pump: handle client → server messages (heartbeat, presence_ping).
    let state_in = state.clone();
    let from_name_in = from_name.clone();
    let recv_task = tokio::spawn(async move {
        // Throttle offline-knock pushes: a knock burst is many taps, but an
        // offline target should get ONE push per burst, not one per tap.
        let mut last_knock_push: Option<(Uuid, std::time::Instant)> = None;
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Text(t) => {
                    if let Ok(v) = serde_json::from_str::<Value>(&t) {
                        match v.get("type").and_then(|x| x.as_str()) {
                            Some("heartbeat") | Some("presence_ping") => {
                                let _ = sqlx::query(
                                    "UPDATE users SET last_seen_at = now() WHERE id = $1",
                                )
                                .bind(uid)
                                .execute(&state_in.db)
                                .await;
                            }
                            // Live "knock": relay each tap to the target user's
                            // sockets in real time. The pattern's rhythm is the
                            // arrival timing of these messages (plus an optional
                            // `dt` for jitter-smoothed playback). No DB, no call
                            // row — a knock is a lightweight presence ping you
                            // can feel. `fromName` is supplied by the sender so
                            // the callee can label it without a lookup.
                            Some("knock") => {
                                if let Some(to) = v
                                    .get("to")
                                    .and_then(|x| x.as_str())
                                    .and_then(|s| Uuid::parse_str(s).ok())
                                {
                                    let out = json!({
                                        "type": "knock",
                                        "fromUserId": uid,
                                        "fromName": from_name_in.clone(),
                                        "seq": v.get("seq"),
                                        "dt": v.get("dt"),
                                        "strength": v.get("strength"),
                                        "final": v.get("final"),
                                        "pattern": v.get("pattern"),
                                    });
                                    let delivered = state_in.hub.publish(to, out).await;
                                    // The tap rhythm is live-only. Closed-app
                                    // knock rings are real call invitations
                                    // created through POST /calls with
                                    // ringStyle="knock", so they have a call id
                                    // and can be reported through CallKit/Telecom.
                                    let fresh_burst = last_knock_push
                                        .map(|(t, at)| t != to || at.elapsed().as_secs() >= 4)
                                        .unwrap_or(true);
                                    if delivered == 0 && fresh_burst {
                                        last_knock_push = Some((to, std::time::Instant::now()));
                                        tracing::info!(
                                            target = %to,
                                            "live knock target offline — not sending non-call push"
                                        );
                                    }
                                }
                            }
                            _ => {}
                        }
                    }
                }
                Message::Ping(_) => { /* axum auto-pongs */ }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    // Tell the user their own socket is live (handy for the client to confirm).
    state.hub.publish(uid, json!({ "type": "connected" })).await;

    // When either side ends, tear down.
    tokio::select! {
        _ = send_task => {}
        _ = recv_task => {}
    }

    state.hub.disconnect(uid, conn_id).await;
}
