//! Phone-only auth: request OTP → verify → tokens; refresh; logout.
//!
//! Three transports for `POST /auth/request-otp` (SPEC.md section 1.4):
//! - `review`: the phone is one of `REVIEW_PHONES` and `REVIEW_OTP_CODE` is
//!   set. No SMS is sent, no OTP challenge is stored — verification compares
//!   the submitted code against `REVIEW_OTP_CODE` directly.
//! - `sms`: a real SMS provider (`sns`/`twilio`) is configured — the backend
//!   sends the code itself (existing Redis-backed challenge).
//! - `firebase`: `SMS_PROVIDER` is the `console` default (production today
//!   without a real provider) — the backend sends nothing and stores no
//!   challenge; the client must run Firebase phone verification itself. With
//!   `EXPOSE_DEV_OTP=true` (local/CI only) this instead behaves like `sms`
//!   plus a `devCode` in the response, for a backend-only smoke test.

use axum::{extract::State, Json};
use constant_time_eq::constant_time_eq;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use slide_core::{
    error::{AppError, AppResult},
    models::{User, USER_COLUMNS},
    otp, phone,
};

use crate::{otp_store, review, state::AppState, tokens, views, views::MeView};

#[derive(Deserialize)]
pub struct RequestOtpBody {
    pub phone: String,
}

/// POST /auth/request-otp — generate + send (or defer to Firebase) a code.
/// Rate-limited per phone regardless of transport.
pub async fn request_otp(
    State(state): State<AppState>,
    Json(body): Json<RequestOtpBody>,
) -> AppResult<Json<Value>> {
    let e164 = phone::normalize_e164(&body.phone, &state.cfg.default_region)?;

    // Rate limit: 1 / 30s and 5 / hour per phone.
    otp_store::rate_limit(&state, &format!("rl:otp:30s:{e164}"), 1, 30).await?;
    otp_store::rate_limit(&state, &format!("rl:otp:1h:{e164}"), 5, 3600).await?;

    if state.cfg.is_review_phone(&e164) && state.cfg.review_login_enabled() {
        // Review: nothing sent, nothing stored — verify-otp compares directly
        // against REVIEW_OTP_CODE.
        return Ok(Json(json!({ "status": "sent", "transport": "review" })));
    }

    if state.cfg.has_real_sms_provider() {
        let code = otp::generate_code();
        let code_hash = otp::hash_code(&code, &e164, &state.cfg.otp_pepper);
        otp_store::put_otp(&state, &e164, &code_hash).await?;
        state.sms.send_code(&e164, &code).await?;
        return Ok(Json(json!({ "status": "sent", "transport": "sms" })));
    }

    // SMS_PROVIDER is "console" — no real transport. In production this means
    // the client must do Firebase phone verification itself; the old
    // behavior (claiming "sent" while nothing was ever sent) is the bug this
    // fixes. EXPOSE_DEV_OTP=true (local/CI only, gated at startup to
    // console-only) restores a fully backend-driven flow for the smoke test.
    if state.cfg.is_dev_sms() {
        let code = otp::generate_code();
        let code_hash = otp::hash_code(&code, &e164, &state.cfg.otp_pepper);
        otp_store::put_otp(&state, &e164, &code_hash).await?;
        Ok(Json(
            json!({ "status": "sent", "transport": "sms", "devCode": code }),
        ))
    } else {
        Ok(Json(json!({ "status": "sent", "transport": "firebase" })))
    }
}

#[derive(Deserialize)]
pub struct VerifyOtpBody {
    pub phone: String,
    pub code: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub is_new_user: bool,
    /// The same shape as `GET /me`, so the client can route straight into
    /// profile setup or home without a second request.
    pub user: MeView,
}

/// Per-phone rate limit on `verify_otp` itself, independent of
/// `otp_store::check_otp`'s per-challenge attempt cap. Without this, the
/// review-phone branch below (a static, non-expiring code with no
/// `request-otp` challenge to exhaust) could be brute-forced as fast as the
/// network allows.
const VERIFY_RATE_LIMIT_PER_MIN: i64 = 10;

/// POST /auth/verify-otp — verify the code, upsert the user, mint tokens.
pub async fn verify_otp(
    State(state): State<AppState>,
    Json(body): Json<VerifyOtpBody>,
) -> AppResult<Json<TokenResponse>> {
    let e164 = phone::normalize_e164(&body.phone, &state.cfg.default_region)?;

    otp_store::rate_limit(
        &state,
        &format!("rl:verify:1m:{e164}"),
        VERIFY_RATE_LIMIT_PER_MIN,
        60,
    )
    .await?;

    if state.cfg.is_review_phone(&e164) && state.cfg.review_login_enabled() {
        let code_is_correct = constant_time_eq(
            body.code.trim().as_bytes(),
            state.cfg.review_otp_code.as_bytes(),
        );
        match otp_store::check_review_code(&state, &e164, code_is_correct).await? {
            otp_store::OtpCheck::Ok => {}
            otp_store::OtpCheck::TooManyAttempts => {
                return Err(AppError::bad_request("too many attempts — try again later"));
            }
            // check_review_code never returns Expired; every other case is a
            // wrong guess.
            _ => return Err(AppError::bad_request("incorrect code")),
        }
    } else {
        match otp_store::check_otp(&state, &e164, &body.code).await? {
            otp_store::OtpCheck::Ok => {}
            otp_store::OtpCheck::Wrong => return Err(AppError::bad_request("incorrect code")),
            otp_store::OtpCheck::Expired => {
                return Err(AppError::bad_request("code expired — request a new one"));
            }
            otp_store::OtpCheck::TooManyAttempts => {
                return Err(AppError::bad_request(
                    "too many attempts — request a new code",
                ));
            }
        }
    }

    issue_session_for_phone(&state, &e164).await.map(Json)
}

/// Upsert the user by phone and mint an access + refresh token pair. Shared by
/// both the OTP flow and Firebase phone auth so they behave identically.
pub async fn issue_session_for_phone(state: &AppState, e164: &str) -> AppResult<TokenResponse> {
    let select_sql = format!("SELECT {USER_COLUMNS} FROM users WHERE phone = $1");
    let existing: Option<User> = sqlx::query_as(&select_sql)
        .bind(e164)
        .fetch_optional(&state.db)
        .await?;

    let (user, is_new_user) = match existing {
        Some(u) => (u, false),
        None => {
            let insert_sql =
                format!("INSERT INTO users (phone) VALUES ($1) RETURNING {USER_COLUMNS}");
            let u: User = sqlx::query_as(&insert_sql)
                .bind(e164)
                .fetch_one(&state.db)
                .await?;
            (u, true)
        }
    };

    if state.cfg.is_review_phone(e164) {
        review::ensure_fixtures(state, &user).await?;
    }
    // Built after fixtures so a review account's token response already shows
    // the seeded, complete profile.
    let user = views::me_view(state, user.id).await?;

    let access_token = state
        .access_signer
        .sign_access(user.id, state.cfg.access_ttl_secs)?;
    let refresh_token = tokens::issue(state, user.id).await?;

    Ok(TokenResponse {
        access_token,
        refresh_token,
        is_new_user,
        user,
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FirebaseAuthBody {
    /// The Firebase ID token obtained on-device after the phone+SMS flow.
    pub id_token: String,
}

/// POST /auth/firebase — verify a Firebase phone-auth ID token and mint Slide
/// session tokens. The phone number comes from the verified token, so there's no
/// separate code to check here (Firebase already verified the SMS on-device).
pub async fn firebase_auth(
    State(state): State<AppState>,
    Json(body): Json<FirebaseAuthBody>,
) -> AppResult<Json<TokenResponse>> {
    let claims = state.firebase.verify(&body.id_token).await?;
    let raw_phone = claims
        .phone_number
        .ok_or_else(|| AppError::bad_request("Firebase token has no phone number"))?;
    let e164 = phone::normalize_e164(&raw_phone, &state.cfg.default_region)?;
    issue_session_for_phone(&state, &e164).await.map(Json)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshBody {
    pub refresh_token: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshResponse {
    pub access_token: String,
    pub refresh_token: String,
}

/// POST /auth/refresh — rotate the refresh token, issue a new access token.
pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshBody>,
) -> AppResult<Json<RefreshResponse>> {
    let (user_id, new_refresh) = tokens::rotate(&state, &body.refresh_token).await?;
    let access_token = state
        .access_signer
        .sign_access(user_id, state.cfg.access_ttl_secs)?;
    Ok(Json(RefreshResponse {
        access_token,
        refresh_token: new_refresh,
    }))
}

/// POST /auth/logout — revoke the refresh token.
pub async fn logout(
    State(state): State<AppState>,
    Json(body): Json<RefreshBody>,
) -> AppResult<axum::http::StatusCode> {
    tokens::revoke(&state, &body.refresh_token).await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}
