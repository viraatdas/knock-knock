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

const CONNECTION_QUEUE_CAPACITY: usize = 128;

pub type Tx = mpsc::Sender<Value>;

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
    pub async fn connect(&self, user_id: Uuid) -> (u64, mpsc::Receiver<Value>) {
        // A bounded queue prevents a suspended or slow client from turning a
        // high-rate event stream into unbounded server memory growth.
        let (tx, rx) = mpsc::channel(CONNECTION_QUEUE_CAPACITY);
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

    /// True if the user has at least one live socket. This is presence only,
    /// never proof that push may be suppressed — a message push still checks
    /// this to decide whether to also send an APNs alert.
    pub async fn is_online(&self, user_id: Uuid) -> bool {
        self.inner.read().await.contains_key(&user_id)
    }

    /// Send an event to every live socket of one user. Returns how many
    /// bounded socket queues accepted it.
    pub async fn publish(&self, user_id: Uuid, event: Value) -> usize {
        let conns: Vec<(u64, Tx)> = {
            let map = self.inner.read().await;
            let Some(conns) = map.get(&user_id) else {
                return 0;
            };
            conns
                .iter()
                .map(|(id, sender)| (*id, sender.clone()))
                .collect()
        };

        let mut delivered = 0;
        let mut failed = Vec::new();
        for (conn_id, tx) in conns {
            match tx.try_send(event.clone()) {
                Ok(()) => delivered += 1,
                Err(error) => {
                    let queue_full = matches!(error, mpsc::error::TrySendError::Full(_));
                    tracing::warn!(
                        user = %user_id,
                        conn_id,
                        queue_full,
                        "dropping stalled signaling connection"
                    );
                    failed.push(conn_id);
                }
            }
        }

        if !failed.is_empty() {
            let mut map = self.inner.write().await;
            if let Some(current) = map.get_mut(&user_id) {
                for conn_id in failed {
                    current.remove(&conn_id);
                }
                if current.is_empty() {
                    map.remove(&user_id);
                }
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

#[cfg(test)]
mod tests {
    use serde_json::json;
    use uuid::Uuid;

    use super::{Hub, CONNECTION_QUEUE_CAPACITY};

    #[tokio::test]
    async fn publishes_to_every_device_connection() {
        let hub = Hub::new();
        let user = Uuid::new_v4();
        let (_, mut first) = hub.connect(user).await;
        let (_, mut second) = hub.connect(user).await;

        assert_eq!(hub.publish(user, json!({ "type": "message" })).await, 2);
        assert_eq!(first.recv().await.unwrap()["type"], "message");
        assert_eq!(second.recv().await.unwrap()["type"], "message");
    }

    #[tokio::test]
    async fn disconnecting_one_device_keeps_the_other_online() {
        let hub = Hub::new();
        let user = Uuid::new_v4();
        let (first_id, _first) = hub.connect(user).await;
        let (_, mut second) = hub.connect(user).await;

        hub.disconnect(user, first_id).await;
        assert!(hub.is_online(user).await);
        assert_eq!(hub.publish(user, json!({ "type": "connected" })).await, 1);
        assert!(second.recv().await.is_some());
    }

    #[tokio::test]
    async fn prunes_closed_and_backpressured_connections() {
        let hub = Hub::new();
        let closed_user = Uuid::new_v4();
        let (_, closed_rx) = hub.connect(closed_user).await;
        drop(closed_rx);
        assert_eq!(hub.publish(closed_user, json!(1)).await, 0);
        assert!(!hub.is_online(closed_user).await);

        let stalled_user = Uuid::new_v4();
        let (_, _stalled_rx) = hub.connect(stalled_user).await;
        for sequence in 0..CONNECTION_QUEUE_CAPACITY {
            assert_eq!(hub.publish(stalled_user, json!(sequence)).await, 1);
        }
        assert_eq!(hub.publish(stalled_user, json!("overflow")).await, 0);
        assert!(!hub.is_online(stalled_user).await);
    }
}
