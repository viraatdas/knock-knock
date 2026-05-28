//! Slide control-plane API (axum). Phone-OTP auth, profile, contacts, call
//! control, and the app-signaling WebSocket.

mod auth;
mod config;
mod hub;
mod otp_store;
mod routes;
mod sfu_client;
mod sms;
mod state;
mod tokens;

use std::time::Duration;

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use crate::{config::Config, hub::Hub, sms::SmsSender, state::AppState};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cfg = Config::from_env();

    // ── Postgres ──
    let db = PgPoolOptions::new()
        .max_connections(20)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&cfg.database_url)
        .await
        .context("connecting to Postgres")?;

    sqlx::migrate!("./migrations")
        .run(&db)
        .await
        .context("running migrations")?;
    tracing::info!("migrations applied");

    // ── Redis ──
    let redis_client = redis::Client::open(cfg.redis_url.clone()).context("opening redis")?;
    let redis = redis::aio::ConnectionManager::new(redis_client)
        .await
        .context("connecting to Redis")?;

    let sms = SmsSender::from_config(&cfg);
    let hub = Hub::new();

    let bind = cfg.api_bind.clone();
    let state = AppState::new(cfg, db, redis, sms, hub);

    let app = routes::router(state)
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive());

    let listener = tokio::net::TcpListener::bind(&bind)
        .await
        .with_context(|| format!("binding {bind}"))?;
    tracing::info!("slide-api listening on http://{bind}");

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<std::net::SocketAddr>(),
    )
    .await
    .context("serving")?;

    Ok(())
}
