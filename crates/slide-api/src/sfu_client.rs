//! Control-plane view of the SFU cluster.
//!
//! For v1 there is a single logical SFU node configured by env. Room
//! allocation is deterministic (room id = call id); the join token is a
//! short-lived JWT signed under the SFU secret that the SFU node validates
//! before admitting a peer. This is the seam where a real least-loaded node
//! picker + cross-node RPC would slot in later.

use uuid::Uuid;

use slide_core::{error::AppResult, turn};

use crate::state::AppState;

pub struct RoomAllocation {
    pub room_id: String,
    pub sfu_node_id: String,
    pub sfu_url: String,
}

/// Allocate (logically) a room for a call on an SFU node.
pub fn allocate_room(state: &AppState, call_id: Uuid) -> RoomAllocation {
    let room_id = call_id.to_string();
    let sfu_node_id = state.cfg.sfu_node_id.clone();
    let sfu_url = format!("{}/ws?room={}", state.cfg.sfu_public_url, room_id);
    RoomAllocation {
        room_id,
        sfu_node_id,
        sfu_url,
    }
}

/// Mint a room-scoped join token for a user.
pub fn mint_join_token(
    state: &AppState,
    user_id: Uuid,
    call_id: Uuid,
    room_id: &str,
    sfu_node_id: &str,
) -> AppResult<String> {
    let token = state.sfu_signer.sign_join(
        user_id,
        call_id,
        room_id,
        sfu_node_id,
        state.cfg.join_ttl_secs,
    )?;
    Ok(token)
}

/// Build the ICE server list (STUN + ephemeral TURN creds) for a joining user.
pub fn ice_servers(state: &AppState, user_id: Uuid) -> Vec<turn::IceServer> {
    turn::ice_servers(
        &state.cfg.turn_shared_secret,
        &state.cfg.turn_uris,
        user_id,
        state.cfg.turn_cred_ttl_secs,
    )
}
