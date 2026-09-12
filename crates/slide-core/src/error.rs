//! Unified error type that renders to a consistent JSON error envelope.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

pub type AppResult<T> = Result<T, AppError>;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,

    #[error("unauthorized")]
    Unauthorized,

    #[error("forbidden")]
    Forbidden,

    #[error("{0}")]
    BadRequest(String),

    /// `code` is the machine-readable `error.code` on the wire (SPEC.md
    /// section 1.6's named preconditions, e.g. `session_closed`); it defaults
    /// to the generic `"conflict"` for call sites that only have a
    /// human-readable message and don't need a specific token.
    #[error("{message}")]
    Conflict { code: &'static str, message: String },

    #[error("too many requests")]
    RateLimited { retry_after_secs: u64 },

    /// See `Conflict`'s `code` doc — same deal, defaulting to `"validation"`.
    #[error("{message}")]
    Validation { code: &'static str, message: String },

    #[error("service unavailable: {0}")]
    Unavailable(String),

    #[error(transparent)]
    Internal(#[from] anyhow::Error),
}

impl AppError {
    pub fn bad_request(msg: impl Into<String>) -> Self {
        Self::BadRequest(msg.into())
    }
    pub fn conflict(msg: impl Into<String>) -> Self {
        Self::Conflict {
            code: "conflict",
            message: msg.into(),
        }
    }
    pub fn validation(msg: impl Into<String>) -> Self {
        Self::Validation {
            code: "validation",
            message: msg.into(),
        }
    }
    /// Like `conflict`, but with `code` as the wire `error.code` instead of
    /// the generic `"conflict"` — for a named precondition a client branches
    /// on (SPEC.md section 1.6, e.g. `session_closed`/`date_not_ended`).
    pub fn conflict_code(code: &'static str, msg: impl Into<String>) -> Self {
        Self::Conflict {
            code,
            message: msg.into(),
        }
    }
    /// Like `validation`, but with `code` as the wire `error.code` (e.g.
    /// `profile_incomplete`/`location_required`).
    pub fn validation_code(code: &'static str, msg: impl Into<String>) -> Self {
        Self::Validation {
            code,
            message: msg.into(),
        }
    }
    pub fn unavailable(msg: impl Into<String>) -> Self {
        Self::Unavailable(msg.into())
    }

    fn parts(&self) -> (StatusCode, &'static str) {
        match self {
            AppError::NotFound => (StatusCode::NOT_FOUND, "not_found"),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized"),
            AppError::Forbidden => (StatusCode::FORBIDDEN, "forbidden"),
            AppError::BadRequest(_) => (StatusCode::BAD_REQUEST, "bad_request"),
            AppError::Conflict { code, .. } => (StatusCode::CONFLICT, code),
            AppError::RateLimited { .. } => (StatusCode::TOO_MANY_REQUESTS, "rate_limited"),
            AppError::Validation { code, .. } => (StatusCode::UNPROCESSABLE_ENTITY, code),
            AppError::Unavailable(_) => (StatusCode::SERVICE_UNAVAILABLE, "unavailable"),
            AppError::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, "internal"),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code) = self.parts();
        // Log server-side faults with full context; never leak internals to clients.
        if let AppError::Internal(ref e) = self {
            tracing::error!(error = ?e, "internal error");
        }
        let message = match &self {
            AppError::Internal(_) => "internal server error".to_string(),
            other => other.to_string(),
        };
        let mut body = json!({ "error": { "code": code, "message": message } });
        if let AppError::RateLimited { retry_after_secs } = &self {
            body["error"]["retryAfter"] = json!(retry_after_secs);
        }
        (status, Json(body)).into_response()
    }
}

// ── Conversions from common error sources ───────────────────────────────────

impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self {
        match e {
            sqlx::Error::RowNotFound => AppError::NotFound,
            other => AppError::Internal(anyhow::Error::new(other)),
        }
    }
}

impl From<jsonwebtoken::errors::Error> for AppError {
    fn from(_: jsonwebtoken::errors::Error) -> Self {
        AppError::Unauthorized
    }
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        AppError::BadRequest(format!("invalid json: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // A named precondition's `code` must reach `error.code` on the wire
    // (SPEC.md 1.6) instead of collapsing to the generic variant name — a
    // client branching on `session_closed`/`profile_incomplete`/
    // `location_required` needs to tell them apart from each other and from
    // an arbitrary field-validation message that also goes through
    // `AppError::validation(...)`.
    #[test]
    fn conflict_code_carries_through_as_the_wire_code() {
        let err = AppError::conflict_code("session_closed", "the doors are closed for tonight");
        assert_eq!(err.parts().1, "session_closed");
    }

    #[test]
    fn validation_code_carries_through_as_the_wire_code() {
        let err = AppError::validation_code("profile_incomplete", "finish your profile");
        assert_eq!(err.parts().1, "profile_incomplete");
    }

    #[test]
    fn plain_conflict_and_validation_default_to_generic_codes() {
        assert_eq!(AppError::conflict("already exists").parts().1, "conflict");
        assert_eq!(AppError::validation("bad input").parts().1, "validation");
    }
}
