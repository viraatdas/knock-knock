//! Phone-only auth: request OTP → verify → tokens; refresh; logout.

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use slide_core::{
    error::{AppError, AppResult},
    models::User,
    otp, phone,
};

use crate::{otp_store, state::AppState, tokens};

#[derive(Deserialize)]
pub struct RequestOtpBody {
    pub phone: String,
}

/// POST /auth/request-otp — generate + send a code. Rate-limited per phone.
pub async fn request_otp(
    State(state): State<AppState>,
    Json(body): Json<RequestOtpBody>,
) -> AppResult<Json<Value>> {
    let e164 = phone::normalize_e164(&body.phone, &state.cfg.default_region)?;

    // Rate limit: 1 / 30s and 5 / hour per phone.
    otp_store::rate_limit(&state, &format!("rl:otp:30s:{e164}"), 1, 30).await?;
    otp_store::rate_limit(&state, &format!("rl:otp:1h:{e164}"), 5, 3600).await?;

    let code = otp::generate_code();
    let code_hash = otp::hash_code(&code, &e164, &state.cfg.otp_pepper);
    otp_store::put_otp(&state, &e164, &code_hash).await?;

    state.sms.send_code(&e164, &code).await?;

    // Only echo the code when explicitly opted in for dev (EXPOSE_DEV_OTP=true,
    // gated at startup to console-only). In production this is false, so the
    // code is delivered solely via SMS and never returned to the caller.
    if state.cfg.is_dev_sms() {
        Ok(Json(json!({ "status": "sent", "devCode": code })))
    } else {
        Ok(Json(json!({ "status": "sent" })))
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
    pub user: User,
}

/// POST /auth/verify-otp — verify the code, upsert the user, mint tokens.
pub async fn verify_otp(
    State(state): State<AppState>,
    Json(body): Json<VerifyOtpBody>,
) -> AppResult<Json<TokenResponse>> {
    let e164 = phone::normalize_e164(&body.phone, &state.cfg.default_region)?;

    match otp_store::check_otp(&state, &e164, &body.code).await? {
        otp_store::OtpCheck::Ok => {}
        otp_store::OtpCheck::Wrong => return Err(AppError::bad_request("incorrect code")),
        otp_store::OtpCheck::Expired => {
            return Err(AppError::bad_request("code expired — request a new one"))
        }
        otp_store::OtpCheck::TooManyAttempts => {
            return Err(AppError::bad_request(
                "too many attempts — request a new code",
            ))
        }
    }

    issue_session_for_phone(&state, &e164).await.map(Json)
}

/// Upsert the user by phone and mint an access + refresh token pair. Shared by
/// both the OTP flow and Firebase phone auth so they behave identically.
pub async fn issue_session_for_phone(
    state: &AppState,
    e164: &str,
) -> AppResult<TokenResponse> {
    let existing: Option<User> = sqlx::query_as("SELECT * FROM users WHERE phone = $1")
        .bind(e164)
        .fetch_optional(&state.db)
        .await?;

    let (user, is_new_user) = match existing {
        Some(u) => (u, false),
        None => {
            let u: User = sqlx::query_as("INSERT INTO users (phone) VALUES ($1) RETURNING *")
                .bind(e164)
                .fetch_one(&state.db)
                .await?;
            (u, true)
        }
    };

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
