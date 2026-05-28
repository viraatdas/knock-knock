//! Slide SFU — selective forwarding unit + signaling node.
//!
//! Clients reach this node at `/ws?room=<id>&token=<joinToken>`. The join token
//! is a JWT minted by the control plane under the shared SFU secret. Each peer
//! negotiates a single WebRTC connection with the SFU, which forwards media to
//! the other peers in the room.

mod config;
mod room;
mod signaling;

use std::sync::Arc;

use anyhow::Context;
use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use serde::Deserialize;
use tokio::sync::mpsc;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};
use uuid::Uuid;
use webrtc::ice_transport::ice_server::RTCIceServer;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::track::track_remote::TrackRemote;

use slide_core::jwt::TokenSigner;

use crate::{
    config::SfuConfig,
    room::{Peer, Room, RoomManager},
    signaling::{ClientMessage, ServerMessage},
};

#[derive(Clone)]
struct SfuState {
    cfg: Arc<SfuConfig>,
    rooms: Arc<RoomManager>,
    signer: Arc<TokenSigner>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cfg = SfuConfig::from_env();
    let signer = TokenSigner::new(&cfg.sfu_jwt_secret);
    let bind = cfg.bind.clone();

    let state = SfuState {
        cfg: Arc::new(cfg),
        rooms: Arc::new(RoomManager::new()),
        signer: Arc::new(signer),
    };

    let app = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/ws", get(ws_upgrade))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(&bind)
        .await
        .with_context(|| format!("binding {bind}"))?;
    tracing::info!(node_id = %state.cfg.node_id, "slide-sfu listening on {bind}");
    axum::serve(listener, app).await.context("serving")?;
    Ok(())
}

#[derive(Deserialize)]
struct WsQuery {
    room: String,
    token: String,
}

async fn ws_upgrade(
    State(state): State<SfuState>,
    Query(q): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Response {
    // Validate the room-scoped join token.
    let claims = match state.signer.verify_join(&q.token) {
        Ok(c) => c,
        Err(_) => return axum::http::StatusCode::UNAUTHORIZED.into_response(),
    };
    if claims.room_id != q.room {
        return axum::http::StatusCode::FORBIDDEN.into_response();
    }
    let user_id = claims.sub;
    let room_id = q.room.clone();
    ws.on_upgrade(move |socket| handle_peer(socket, state, room_id, user_id))
}

fn ice_servers(cfg: &SfuConfig, user_id: Uuid) -> Vec<RTCIceServer> {
    slide_core::turn::ice_servers(
        &cfg.turn_shared_secret,
        &cfg.turn_uris,
        user_id,
        cfg.turn_cred_ttl_secs,
    )
    .into_iter()
    .map(|s| RTCIceServer {
        urls: s.urls,
        username: s.username.unwrap_or_default(),
        credential: s.credential.unwrap_or_default(),
    })
    .collect()
}

async fn handle_peer(socket: WebSocket, state: SfuState, room_id: String, user_id: Uuid) {
    use futures::{SinkExt, StreamExt};

    let room = state.rooms.get_or_create(&room_id).await;

    // Build this peer's connection.
    let pc = match room::new_peer_connection(ice_servers(&state.cfg, user_id)).await {
        Ok(pc) => pc,
        Err(e) => {
            tracing::error!(error = %e, "failed to create peer connection");
            return;
        }
    };

    let (out_tx, mut out_rx) = mpsc::unbounded_channel::<ServerMessage>();
    let peer = Arc::new(Peer {
        user_id,
        pc: pc.clone(),
        tx: out_tx.clone(),
        neg_lock: tokio::sync::Mutex::new(()),
    });

    // ICE candidates from the SFU → client.
    {
        let tx = out_tx.clone();
        pc.on_ice_candidate(Box::new(move |cand| {
            let tx = tx.clone();
            Box::pin(async move {
                if let Some(c) = cand {
                    if let Ok(init) = c.to_json() {
                        let _ = tx.send(ServerMessage::Ice {
                            candidate: init.candidate,
                            sdp_mid: init.sdp_mid,
                            sdp_mline_index: init.sdp_mline_index,
                        });
                    }
                }
            })
        }));
    }

    // Connection state logging.
    pc.on_peer_connection_state_change(Box::new(move |s: RTCPeerConnectionState| {
        Box::pin(async move {
            tracing::info!(?s, "peer connection state");
        })
    }));

    // Incoming media: build a forwarding track and fan it out.
    {
        let room = room.clone();
        let publisher = user_id;
        pc.on_track(Box::new(move |remote: Arc<TrackRemote>, _recv, _trans| {
            let room = room.clone();
            Box::pin(async move {
                let codec = remote.codec();
                let cap = RTCRtpCodecCapability {
                    mime_type: codec.capability.mime_type.clone(),
                    clock_rate: codec.capability.clock_rate,
                    channels: codec.capability.channels,
                    sdp_fmtp_line: codec.capability.sdp_fmtp_line.clone(),
                    rtcp_feedback: codec.capability.rtcp_feedback.clone(),
                };
                let kind = remote.kind().to_string();
                let local = room::make_forward_track(cap, publisher, &kind);
                let published = Arc::new(room::PublishedTrack {
                    publisher,
                    local: local.clone(),
                });
                if let Err(e) = room.publish_track(published).await {
                    tracing::warn!(error = %e, "publish_track failed");
                }
                room::pump_rtp(remote, local).await;
            })
        }));
    }

    room.add_peer(peer.clone()).await;
    notify_room(
        &room,
        user_id,
        ServerMessage::PeerJoined {
            user_id: user_id.to_string(),
        },
    )
    .await;

    let (mut sink, mut stream) = socket.split();

    // Outbound: server messages → socket.
    let send_task = tokio::spawn(async move {
        while let Some(msg) = out_rx.recv().await {
            let Ok(txt) = serde_json::to_string(&msg) else {
                continue;
            };
            if sink.send(Message::Text(txt.into())).await.is_err() {
                break;
            }
        }
    });

    // Inbound: client signaling.
    let peer_in = peer.clone();
    let room_in = room.clone();
    let recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = stream.next().await {
            if let Message::Text(t) = msg {
                let Ok(cm) = serde_json::from_str::<ClientMessage>(&t) else {
                    continue;
                };
                match cm {
                    ClientMessage::Offer { sdp } => {
                        match room::handle_client_offer(&peer_in, &room_in, sdp).await {
                            Ok(answer) => {
                                let _ = peer_in.tx.send(ServerMessage::Answer { sdp: answer });
                            }
                            Err(e) => {
                                let _ = peer_in.tx.send(ServerMessage::Error {
                                    message: e.to_string(),
                                });
                            }
                        }
                    }
                    ClientMessage::Answer { sdp } => {
                        let _ = room::handle_client_answer(&peer_in, sdp).await;
                    }
                    ClientMessage::Ice {
                        candidate,
                        sdp_mid,
                        sdp_mline_index,
                    } => {
                        let _ =
                            room::handle_client_ice(&peer_in, candidate, sdp_mid, sdp_mline_index)
                                .await;
                    }
                    ClientMessage::Ping => {
                        let _ = peer_in.tx.send(ServerMessage::Pong);
                    }
                }
            } else if let Message::Close(_) = msg {
                break;
            }
        }
    });

    tokio::select! {
        _ = send_task => {}
        _ = recv_task => {}
    }

    // Teardown.
    let _ = pc.close().await;
    room.remove_peer(user_id).await;
    notify_room(
        &room,
        user_id,
        ServerMessage::PeerLeft {
            user_id: user_id.to_string(),
        },
    )
    .await;
}

async fn notify_room(room: &Arc<Room>, except: Uuid, msg: ServerMessage) {
    for p in room.other_peers(except).await {
        // ServerMessage isn't Clone; re-serialize per peer.
        let cloned = match &msg {
            ServerMessage::PeerJoined { user_id } => ServerMessage::PeerJoined {
                user_id: user_id.clone(),
            },
            ServerMessage::PeerLeft { user_id } => ServerMessage::PeerLeft {
                user_id: user_id.clone(),
            },
            _ => continue,
        };
        let _ = p.tx.send(cloned);
    }
}
