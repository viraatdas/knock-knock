//! Bearer-token authentication: an axum extractor that validates the access
//! JWT and yields the authenticated user id.

use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts},
};
use uuid::Uuid;

use slide_core::error::AppError;

use crate::state::AppState;

/// Extractor that requires a valid `Authorization: Bearer <accessToken>`.
pub struct AuthUser(pub Uuid);

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "))
            .ok_or(AppError::Unauthorized)?;

        let claims = state.access_signer.verify_access(token)?;
        Ok(AuthUser(claims.sub))
    }
}

/// Extract a bearer/`?token=` access token id without the full extractor —
/// used by the WebSocket upgrade, which carries the token as a query param.
pub fn verify_query_token(state: &AppState, token: &str) -> Result<Uuid, AppError> {
    Ok(state.access_signer.verify_access(token)?.sub)
}
