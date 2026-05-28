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
};

use serde_json::Value;
use tokio::sync::{mpsc, RwLock};
use uuid::Uuid;

pub type Tx = mpsc::UnboundedSender<Value>;

#[derive(Clone, Default)]
pub struct Hub {
    inner: Arc<RwLock<HashMap<Uuid, HashMap<u64, Tx>>>>,
    next_conn: Arc<AtomicU64>,
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
        (conn_id, rx)
    }

    pub async fn disconnect(&self, user_id: Uuid, conn_id: u64) {
        let mut map = self.inner.write().await;
        if let Some(conns) = map.get_mut(&user_id) {
            conns.remove(&conn_id);
            if conns.is_empty() {
                map.remove(&user_id);
            }
        }
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
