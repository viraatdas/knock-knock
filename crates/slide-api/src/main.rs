//! Knock Knock - 5 Minute Dates control-plane API (axum). Phone-OTP auth, profile,
//! the nightly lobby/date/match/chat flow, and the app-signaling WebSocket.

mod auth;
mod config;
mod firebase;
mod geo;
mod hub;
mod livekit;
mod matcher;
mod otp_store;
mod push;
mod review;
mod routes;
mod scheduler;
mod session;
mod sms;
mod state;
mod tokens;
mod views;

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

    // ── Safety guards: fail loudly instead of shipping an insecure config ──
    // The OTP code may only be echoed in API responses when SMS is the console
    // (dev) provider. With a real provider, exposing it is an auth bypass.
    if cfg.expose_dev_otp && cfg.sms_provider != "console" {
        anyhow::bail!(
            "EXPOSE_DEV_OTP=true with SMS_PROVIDER={} would leak OTP codes — refusing to start",
            cfg.sms_provider
        );
    }
    let any_livekit_config = !cfg.livekit_url.is_empty()
        || !cfg.livekit_api_key.is_empty()
        || !cfg.livekit_api_secret.is_empty();
    if any_livekit_config
        && (cfg.livekit_url.is_empty()
            || cfg.livekit_api_key.is_empty()
            || cfg.livekit_api_secret.is_empty())
    {
        anyhow::bail!(
            "LiveKit is partially configured; set LIVEKIT_URL, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET"
        );
    }
    if !any_livekit_config {
        tracing::error!("LiveKit is disabled; dates cannot mint a video join token");
    }
    let apns_credentials_present =
        !cfg.apns_key_id.is_empty() || !cfg.apns_team_id.is_empty() || !cfg.apns_key_p8.is_empty();
    if apns_credentials_present
        && (cfg.apns_key_id.is_empty()
            || cfg.apns_team_id.is_empty()
            || cfg.apns_key_p8.is_empty()
            || cfg.apns_topic.is_empty())
    {
        anyhow::bail!("APNs is partially configured; set credentials and a non-empty APNS_TOPIC");
    }
    if apns_credentials_present && !matches!(cfg.apns_env.as_str(), "sandbox" | "prod") {
        anyhow::bail!("APNS_ENV must be sandbox or prod");
    }
    if !cfg.review_phones.is_empty() && cfg.review_otp_code.is_empty() {
        tracing::error!(
            "REVIEW_PHONES is set but REVIEW_OTP_CODE is empty; review login is disabled"
        );
    }

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

    let sms = SmsSender::from_config(&cfg).await;
    let hub = Hub::new();

    let bind = cfg.api_bind.clone();
    let state = AppState::new(cfg, db, redis, sms, hub);
    tracing::info!(providers = %state.push.enabled_summary(), "push notifications");
    if !state.push.any_enabled() {
        tracing::error!("push is disabled; matches/messages/doors-open won't reach closed apps");
    }

    tokio::spawn(matcher::run(state.clone()));
    tokio::spawn(routes::dates::run_date_expirer(state.clone()));
    tokio::spawn(scheduler::run(state.clone()));

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
