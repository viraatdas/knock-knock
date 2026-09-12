//! HTTP route table.

pub mod auth;
pub mod chat;
pub mod dates;
pub mod profile;
pub mod safety;
pub mod users;
pub mod ws;

use axum::{
    routing::{get, post},
    Router,
};

use crate::state::AppState;

pub fn router(state: AppState) -> Router {
    let v1 = Router::new()
        // health
        .route("/health", get(|| async { "ok" }))
        // auth
        .route("/auth/request-otp", post(auth::request_otp))
        .route("/auth/verify-otp", post(auth::verify_otp))
        .route("/auth/firebase", post(auth::firebase_auth))
        .route("/auth/refresh", post(auth::refresh))
        .route("/auth/logout", post(auth::logout))
        // session
        .route("/session", get(profile::get_session))
        // profile
        .route(
            "/me",
            get(profile::get_me)
                .patch(profile::patch_me)
                .delete(profile::delete_me),
        )
        .route(
            "/me/photo",
            axum::routing::put(profile::put_photo).delete(profile::delete_photo),
        )
        .route("/users/{id}/photo", get(profile::get_user_photo))
        .route("/me/location", axum::routing::put(profile::put_location))
        // devices + push
        .route("/devices", post(users::register_device))
        .route(
            "/push/register",
            post(users::register_push).delete(users::unregister_push),
        )
        // lobby + dates
        .route("/lobby/join", post(dates::lobby_join))
        .route("/lobby/heartbeat", post(dates::lobby_heartbeat))
        .route("/lobby", axum::routing::delete(dates::lobby_leave))
        .route("/dates/current", get(dates::current_date))
        .route("/dates/today", get(dates::today_dates))
        .route("/dates/{id}/leave", post(dates::leave_date))
        .route("/dates/{id}/decision", post(dates::decide_date))
        // matches + chat
        .route("/matches", get(chat::list_matches))
        .route(
            "/matches/{id}/messages",
            get(chat::list_messages).post(chat::post_message),
        )
        .route("/matches/{id}/read", post(chat::mark_read))
        .route("/matches/{id}", axum::routing::delete(chat::unmatch))
        // safety
        .route(
            "/users/{id}/block",
            post(safety::block_user).delete(safety::unblock_user),
        )
        .route("/users/{id}/report", post(safety::report_user))
        // realtime
        .route("/ws", get(ws::ws_handler))
        .with_state(state);

    Router::new().nest("/v1", v1)
}
