//! In-memory fan-out hub for the app-signaling WebSocket.
//!
//! Maps each connected `user_id` to one or more live connections (a user may
//! have several devices). Handlers publish JSON events to a user; every live
//! socket for that user receives them. Presence is "is there ≥1 live socket".
//!
//! For a single API node this is sufficient. Scaling to multiple nodes later
//! means backing this with Redis pub/sub — the publish API stays the same.

use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Instant,
};

use serde_json::Value;
use tokio::sync::{mpsc, RwLock};
use uuid::Uuid;

pub type Tx = mpsc::UnboundedSender<Value>;

#[derive(Clone, Default)]
pub struct Hub {
    inner: Arc<RwLock<HashMap<Uuid, HashMap<u64, Tx>>>>,
    next_conn: Arc<AtomicU64>,
    /// When each user last sent us anything inbound on a socket. iOS suspends
    /// apps WITHOUT closing the WebSocket, so "has a live socket" overstates
    /// liveness for ~30-60s after backgrounding; this lets callers detect a
    /// stale-but-open socket and fall back to push.
    activity: Arc<RwLock<HashMap<Uuid, Instant>>>,
}

impl Hub {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a new connection for `user_id`, returning its receiver and a
    /// connection id to deregister with on disconnect.
    pub async fn connect(&self, user_id: Uuid) -> (u64, mpsc::UnboundedReceiver<Value>) {
        let (tx, rx) = mpsc::unbounded_channel();
        let conn_id = self.next_conn.fetch_add(1, Ordering::Relaxed);
        let mut map = self.inner.write().await;
        map.entry(user_id).or_default().insert(conn_id, tx);
        drop(map);
        // A fresh connection counts as activity.
        self.touch(user_id).await;
        (conn_id, rx)
    }

    pub async fn disconnect(&self, user_id: Uuid, conn_id: u64) {
        let mut map = self.inner.write().await;
        if let Some(conns) = map.get_mut(&user_id) {
            conns.remove(&conn_id);
            if conns.is_empty() {
                map.remove(&user_id);
                // Last socket gone — drop the activity entry so the map stays
                // bounded by currently-connected users.
                drop(map);
                self.activity.write().await.remove(&user_id);
            }
        }
    }

    /// Record inbound activity from `user_id` (any client → server message).
    pub async fn touch(&self, user_id: Uuid) {
        self.activity.write().await.insert(user_id, Instant::now());
    }

    /// When this user last sent us an inbound message on any socket. `None`
    /// means no live socket (or nothing heard since connect bookkeeping was
    /// cleared) — callers should treat that as stale.
    pub async fn last_activity(&self, user_id: Uuid) -> Option<Instant> {
        self.activity.read().await.get(&user_id).copied()
    }

    /// True if the user has at least one live socket. Used by presence + the
    /// push-fallback decision once APNs/FCM is wired.
    #[allow(dead_code)]
    pub async fn is_online(&self, user_id: Uuid) -> bool {
        self.inner.read().await.contains_key(&user_id)
    }

    /// Send an event to every live socket of one user. Returns how many
    /// sockets received it (0 ⇒ user is offline → caller should fall back to
    /// push notifications).
    pub async fn publish(&self, user_id: Uuid, event: Value) -> usize {
        let map = self.inner.read().await;
        let Some(conns) = map.get(&user_id) else {
            return 0;
        };
        let mut delivered = 0;
        for tx in conns.values() {
            if tx.send(event.clone()).is_ok() {
                delivered += 1;
            }
        }
        delivered
    }

    /// Fan out to many users at once.
    pub async fn publish_many(&self, user_ids: &[Uuid], event: &Value) {
        for uid in user_ids {
            self.publish(*uid, event.clone()).await;
        }
    }
}
