//! App-signaling WebSocket: `GET /v1/ws?token=<accessToken>`.
//!
//! Carries date/match/chat lifecycle events to the client (see SPEC.md
//! section 1.9): `date_matched`, `date_ended`, `match_made`, `match_removed`,
//! `message`, `connected`. The token is passed as a query parameter because
//! browsers/native sockets can't easily set the Authorization header on the
//! upgrade request. On connect we mark the user present; on disconnect,
//! absent.

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
    ws.max_message_size(16 * 1024)
        .max_frame_size(16 * 1024)
        .on_upgrade(move |socket| handle_socket(socket, state, uid))
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

async fn handle_socket(socket: WebSocket, state: AppState, uid: Uuid) {
    use futures::{SinkExt, StreamExt};
    use std::time::Duration;

    let (mut sender, mut receiver) = socket.split();
    let (conn_id, mut rx) = state.hub.connect(uid).await;

    // Announce presence to nobody in particular yet; mark last_seen.
    let _ = sqlx::query("UPDATE users SET last_seen_at = now() WHERE id = $1")
        .bind(uid)
        .execute(&state.db)
        .await;

    // Outbound pump: hub events → socket.
    let mut send_task = tokio::spawn(async move {
        while let Some(evt) = rx.recv().await {
            let txt = evt.to_string();
            if sender.send(Message::Text(txt.into())).await.is_err() {
                break;
            }
        }
    });

    // Inbound pump: handle client → server messages (heartbeat, presence_ping).
    let state_in = state.clone();
    let mut recv_task = tokio::spawn(async move {
        loop {
            // Native clients heartbeat every 25s. Retire sockets that stop
            // speaking instead of treating an iOS-suspended TCP connection as
            // presence forever. Foreground clients reconnect automatically.
            let next = tokio::time::timeout(Duration::from_secs(90), receiver.next()).await;
            let Some(Ok(msg)) = next.ok().flatten() else {
                break;
            };
            match msg {
                Message::Text(t) => {
                    if let Ok(v) = serde_json::from_str::<Value>(&t) {
                        if matches!(
                            v.get("type").and_then(|x| x.as_str()),
                            Some("heartbeat") | Some("presence_ping")
                        ) {
                            let _ =
                                sqlx::query("UPDATE users SET last_seen_at = now() WHERE id = $1")
                                    .bind(uid)
                                    .execute(&state_in.db)
                                    .await;
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
        _ = &mut send_task => recv_task.abort(),
        _ = &mut recv_task => send_task.abort(),
    }

    state.hub.disconnect(uid, conn_id).await;
}
