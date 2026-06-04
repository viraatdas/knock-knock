//! Room + peer management and the selective-forwarding media path.
//!
//! Each client maintains ONE `RTCPeerConnection` with the SFU. The SFU:
//!   1. accepts the client's offer (its published audio/video tracks),
//!   2. for every track another peer in the room has published, adds a
//!      forwarding `TrackLocalStaticRTP` to this peer and (re)negotiates,
//!   3. pumps RTP packets from each publisher's remote track into the matching
//!      local tracks held by every other peer.
//!
//! This is the classic webrtc-rs SFU pattern (one uplink in, many downlinks
//! out) and is the seam where simulcast layer selection would later live.

use std::sync::Arc;

use anyhow::Result;
use tokio::sync::{mpsc, Mutex, RwLock};
use uuid::Uuid;
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::setting_engine::SettingEngine;
use webrtc::api::APIBuilder;
use webrtc::ice::udp_network::{EphemeralUDP, UDPNetwork};
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
use webrtc::ice_transport::ice_candidate_type::RTCIceCandidateType;
use webrtc::ice_transport::ice_server::RTCIceServer;
use webrtc::interceptor::registry::Registry;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::track::track_local::track_local_static_rtp::TrackLocalStaticRTP;
use webrtc::track::track_local::{TrackLocal, TrackLocalWriter};

use crate::signaling::ServerMessage;

/// A single forwarding track: RTP read off a publisher's remote track is
/// written here, and this is added to every subscriber's peer connection.
pub struct PublishedTrack {
    pub publisher: Uuid,
    pub local: Arc<TrackLocalStaticRTP>,
}

pub struct Peer {
    pub user_id: Uuid,
    pub pc: Arc<RTCPeerConnection>,
    /// Outbound signaling channel to this peer's WebSocket task.
    pub tx: mpsc::UnboundedSender<ServerMessage>,
    /// Serializes SDP negotiation for this peer.
    pub neg_lock: Mutex<()>,
}

#[derive(Default)]
pub struct Room {
    pub peers: RwLock<Vec<Arc<Peer>>>,
    pub tracks: RwLock<Vec<Arc<PublishedTrack>>>,
}

#[derive(Default)]
pub struct RoomManager {
    rooms: RwLock<std::collections::HashMap<String, Arc<Room>>>,
}

impl RoomManager {
    pub fn new() -> Self {
        Self::default()
    }

    pub async fn get_or_create(&self, room_id: &str) -> Arc<Room> {
        {
            let r = self.rooms.read().await;
            if let Some(room) = r.get(room_id) {
                return room.clone();
            }
        }
        let mut w = self.rooms.write().await;
        w.entry(room_id.to_string())
            .or_insert_with(|| Arc::new(Room::default()))
            .clone()
    }
}

/// Build a peer connection. All media is muxed onto one shared UDP socket; when
/// `public_ip` is set we advertise it as a 1:1-NAT host candidate so clients
/// connect to the SFU directly (the SFU has no public UDP otherwise, and pure
/// relay-to-relay through one TURN doesn't reliably connect).
pub async fn new_peer_connection(
    ice_servers: Vec<RTCIceServer>,
    public_ip: Option<String>,
    udp_ports: (u16, u16),
) -> Result<Arc<RTCPeerConnection>> {
    let mut m = MediaEngine::default();
    m.register_default_codecs()?;
    let mut registry = Registry::new();
    registry = register_default_interceptors(registry, &mut m)?;

    let mut se = SettingEngine::default();
    se.set_udp_network(UDPNetwork::Ephemeral(EphemeralUDP::new(
        udp_ports.0,
        udp_ports.1,
    )?));
    // Gather ICE on the primary interface only. On a host with docker bridges
    // (docker0 172.17/16) + IPv6 link-local, gathering on those causes
    // asymmetric routing: STUN checks pass but DTLS replies leave the wrong
    // interface and the handshake never completes. Keep IPv4, drop docker +
    // loopback so every packet uses the real NIC (1:1-NAT'd to public_ip).
    se.set_ip_filter(Box::new(|ip: std::net::IpAddr| match ip {
        std::net::IpAddr::V4(v4) => {
            let o = v4.octets();
            !v4.is_loopback() && !(o[0] == 172 && o[1] == 17)
        }
        std::net::IpAddr::V6(_) => false,
    }));
    if let Some(ip) = public_ip {
        se.set_nat_1to1_ips(vec![ip], RTCIceCandidateType::Host);
    }

    let api = APIBuilder::new()
        .with_media_engine(m)
        .with_interceptor_registry(registry)
        .with_setting_engine(se)
        .build();

    let config = RTCConfiguration {
        ice_servers,
        ..Default::default()
    };
    Ok(Arc::new(api.new_peer_connection(config).await?))
}

impl Room {
    pub async fn add_peer(&self, peer: Arc<Peer>) {
        self.peers.write().await.push(peer);
    }

    pub async fn remove_peer(&self, user_id: Uuid) {
        self.peers.write().await.retain(|p| p.user_id != user_id);
        self.tracks.write().await.retain(|t| t.publisher != user_id);
    }

    pub async fn other_peers(&self, except: Uuid) -> Vec<Arc<Peer>> {
        self.peers
            .read()
            .await
            .iter()
            .filter(|p| p.user_id != except)
            .cloned()
            .collect()
    }

    /// Register a new published track and fan it out to every other peer,
    /// renegotiating each via an SFU-initiated offer.
    pub async fn publish_track(self: &Arc<Self>, track: Arc<PublishedTrack>) -> Result<()> {
        self.tracks.write().await.push(track.clone());
        for peer in self.other_peers(track.publisher).await {
            let local: Arc<dyn TrackLocal + Send + Sync> = track.local.clone();
            if peer.pc.add_track(local).await.is_ok() {
                if let Err(e) = renegotiate(&peer).await {
                    tracing::warn!(error = %e, peer = %peer.user_id, "renegotiation failed");
                }
            }
        }
        Ok(())
    }

    /// When a peer joins, give it forwarding tracks for everything already
    /// published in the room.
    pub async fn subscribe_existing(&self, peer: &Arc<Peer>) -> Result<()> {
        let tracks = self.tracks.read().await.clone();
        for t in tracks {
            if t.publisher == peer.user_id {
                continue;
            }
            let local: Arc<dyn TrackLocal + Send + Sync> = t.local.clone();
            let _ = peer.pc.add_track(local).await;
        }
        Ok(())
    }
}

/// SFU-initiated renegotiation: create an offer, set it local, send to peer.
/// The peer replies with an `answer` over signaling.
pub async fn renegotiate(peer: &Arc<Peer>) -> Result<()> {
    let _guard = peer.neg_lock.lock().await;
    let offer = peer.pc.create_offer(None).await?;
    peer.pc.set_local_description(offer.clone()).await?;
    let _ = peer.tx.send(ServerMessage::Offer { sdp: offer.sdp });
    Ok(())
}

/// Handle a client's initial offer: set remote, attach existing tracks, answer.
pub async fn handle_client_offer(
    peer: &Arc<Peer>,
    room: &Arc<Room>,
    sdp: String,
) -> Result<String> {
    let _guard = peer.neg_lock.lock().await;
    let offer = RTCSessionDescription::offer(sdp)?;
    peer.pc.set_remote_description(offer).await?;

    // Attach forwarding tracks for media already in the room.
    room.subscribe_existing(peer).await?;

    let answer = peer.pc.create_answer(None).await?;
    peer.pc.set_local_description(answer.clone()).await?;
    Ok(answer.sdp)
}

pub async fn handle_client_answer(peer: &Arc<Peer>, sdp: String) -> Result<()> {
    let answer = RTCSessionDescription::answer(sdp)?;
    peer.pc.set_remote_description(answer).await?;
    Ok(())
}

pub async fn handle_client_ice(
    peer: &Arc<Peer>,
    candidate: String,
    sdp_mid: Option<String>,
    sdp_mline_index: Option<u16>,
) -> Result<()> {
    peer.pc
        .add_ice_candidate(RTCIceCandidateInit {
            candidate,
            sdp_mid,
            sdp_mline_index,
            username_fragment: None,
        })
        .await?;
    Ok(())
}

/// Build a forwarding local track that mirrors a publisher's remote track's codec.
pub fn make_forward_track(
    capability: RTCRtpCodecCapability,
    publisher: Uuid,
    kind: &str,
) -> Arc<TrackLocalStaticRTP> {
    Arc::new(TrackLocalStaticRTP::new(
        capability,
        format!("{kind}-{publisher}"),
        format!("slide-{publisher}"),
    ))
}

/// Pump RTP from a publisher's remote track into its forwarding local track.
pub async fn pump_rtp(
    remote: Arc<webrtc::track::track_remote::TrackRemote>,
    local: Arc<TrackLocalStaticRTP>,
) {
    while let Ok((packet, _attrs)) = remote.read_rtp().await {
        if local.write_rtp(&packet).await.is_err() {
            break;
        }
    }
}
