//! Profile + session (SPEC.md section 1.5 and 1.3).

use axum::{
    body::Bytes,
    extract::{FromRequest, Multipart, Path, Request, State},
    http::{
        header::{CACHE_CONTROL, CONTENT_TYPE},
        StatusCode,
    },
    response::{IntoResponse, Response},
    Json,
};
use chrono::{DateTime, NaiveDate, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use slide_core::{
    error::{AppError, AppResult},
    models::{User, USER_COLUMNS},
};

use crate::{
    auth::AuthUser,
    session::SessionWindow,
    state::AppState,
    views::{self, MeView},
};

// ── Validation constants ─────────────────────────────────────────────────────

const MAX_DISPLAY_NAME_CHARS: usize = 40;
const MAX_BIO_CHARS: usize = 300;
const MIN_AGE_YEARS: i32 = 18;
const MAX_AGE_YEARS: i32 = 100;
const MIN_AGE_PREF: i16 = 18;
const MAX_AGE_PREF: i16 = 99;
const ALLOWED_GENDERS: [&str; 3] = ["woman", "man", "nonbinary"];
/// 600 KB, per SPEC 1.5. The client resizes to a max 1024px JPEG at q0.8
/// before uploading, so a legitimate photo is well under this.
const MAX_PHOTO_BYTES: usize = 600 * 1024;
const JPEG_MAGIC: [u8; 3] = [0xFF, 0xD8, 0xFF];

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionResponse {
    #[serde(flatten)]
    pub window: SessionWindow,
    pub timezone: String,
    pub date_seconds: i64,
    pub radius_miles: f64,
}

/// GET /session (auth). `SessionWindow::compute` does all the window math;
/// this loads the caller's `is_review_account` flag so review accounts see
/// the session as always open per SPEC 1.10, then adds the config fields the
/// client also wants (timezone name, date length, radius).
pub async fn get_session(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<SessionResponse>> {
    let user = views::self_or_unauthorized(fetch_user(&state, uid).await)?;
    let window = SessionWindow::compute(&state.cfg, chrono::Utc::now(), user.is_review_account);
    Ok(Json(SessionResponse {
        window,
        timezone: state.cfg.session_tz.to_string(),
        date_seconds: state.cfg.date_seconds,
        radius_miles: state.cfg.match_radius_miles,
    }))
}

/// GET /me.
pub async fn get_me(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<Json<MeView>> {
    views::me_view(&state, uid).await.map(Json)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PatchMeBody {
    pub display_name: Option<String>,
    pub birthdate: Option<chrono::NaiveDate>,
    pub gender: Option<String>,
    pub interested_in: Option<Vec<String>>,
    pub age_min: Option<i16>,
    pub age_max: Option<i16>,
    pub bio: Option<String>,
}

async fn fetch_user(state: &AppState, id: Uuid) -> AppResult<User> {
    let sql = format!("SELECT {USER_COLUMNS} FROM users WHERE id = $1");
    sqlx::query_as::<_, User>(&sql)
        .bind(id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)
}

/// `displayName` is a single-line field shown verbatim to other users and
/// used as the push-notification title (see `dates::decide_date`,
/// `chat::post_message`), so it rejects every control character, including
/// newline/tab — unlike `validate_bio`/`validate_message_body`, which allow
/// those for a readable multi-line field.
fn validate_display_name(name: &str) -> AppResult<String> {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.chars().count() > MAX_DISPLAY_NAME_CHARS {
        return Err(AppError::validation(
            "displayName must be 1 to 40 characters",
        ));
    }
    if trimmed.chars().any(|c| c.is_control()) {
        return Err(AppError::validation(
            "displayName has characters that aren't allowed",
        ));
    }
    Ok(trimmed.to_string())
}

fn validate_gender(gender: &str) -> AppResult<String> {
    let trimmed = gender.trim();
    if !ALLOWED_GENDERS.contains(&trimmed) {
        return Err(AppError::validation(
            "gender must be woman, man, or nonbinary",
        ));
    }
    Ok(trimmed.to_string())
}

/// Dedupe and validate `interestedIn`: a non-empty subset of the allowed
/// genders, order of first appearance preserved.
fn validate_interested_in(values: Vec<String>) -> AppResult<Vec<String>> {
    let mut out: Vec<String> = Vec::new();
    for v in values {
        let v = v.trim().to_string();
        if !ALLOWED_GENDERS.contains(&v.as_str()) {
            return Err(AppError::validation(
                "interestedIn must only contain woman, man, or nonbinary",
            ));
        }
        if !out.contains(&v) {
            out.push(v);
        }
    }
    if out.is_empty() {
        return Err(AppError::validation("interestedIn must not be empty"));
    }
    Ok(out)
}

/// Rejects control characters other than newline/tab, same as
/// `chat::validate_message_body` — a NUL byte would otherwise reach Postgres
/// (which rejects it, surfacing as a confusing 500) and bio is shown verbatim
/// on `PublicProfile`.
fn validate_bio(bio: &str) -> AppResult<String> {
    let trimmed = bio.trim();
    if trimmed.chars().count() > MAX_BIO_CHARS {
        return Err(AppError::validation("bio must be 300 characters or fewer"));
    }
    if trimmed
        .chars()
        .any(|c| c.is_control() && c != '\n' && c != '\t')
    {
        return Err(AppError::validation(
            "bio has characters that aren't allowed",
        ));
    }
    Ok(trimmed.to_string())
}

fn validate_age_range(age_min: i16, age_max: i16) -> AppResult<()> {
    if age_min < MIN_AGE_PREF || age_max > MAX_AGE_PREF || age_min > age_max {
        return Err(AppError::validation(
            "ageMin/ageMax must satisfy 18 <= ageMin <= ageMax <= 99",
        ));
    }
    Ok(())
}

/// Age must land in [18, 100] as of `now`, computed on the calendar date in
/// `tz` (matches `views::age_from_birthdate`, which this reuses).
fn validate_birthdate(birthdate: NaiveDate, tz: Tz, now: DateTime<Utc>) -> AppResult<()> {
    let age = views::age_from_birthdate(birthdate, tz, now);
    if !(MIN_AGE_YEARS..=MAX_AGE_YEARS).contains(&age) {
        return Err(AppError::validation("you have to be between 18 and 100"));
    }
    Ok(())
}

/// PATCH /me. Merges the provided fields onto the current row, validating
/// each one that's present, then writes the merged result in one statement.
/// `profile_completed_at` is set once (never unset) the first time the merged
/// state has displayName/birthdate/gender/interestedIn all present.
pub async fn patch_me(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<PatchMeBody>,
) -> AppResult<Json<MeView>> {
    let current = views::self_or_unauthorized(fetch_user(&state, uid).await)?;
    let now = Utc::now();

    let display_name = match body.display_name {
        Some(v) => Some(validate_display_name(&v)?),
        None => current.display_name.clone(),
    };
    let birthdate = match body.birthdate {
        Some(b) => {
            validate_birthdate(b, state.cfg.session_tz, now)?;
            Some(b)
        }
        None => current.birthdate,
    };
    let gender = match body.gender {
        Some(g) => Some(validate_gender(&g)?),
        None => current.gender.clone(),
    };
    let interested_in = match body.interested_in {
        Some(v) => validate_interested_in(v)?,
        None => current.interested_in.clone(),
    };
    let age_min = body.age_min.unwrap_or(current.age_min);
    let age_max = body.age_max.unwrap_or(current.age_max);
    validate_age_range(age_min, age_max)?;
    let bio = match body.bio {
        Some(b) => validate_bio(&b)?,
        None => current.bio.clone(),
    };

    let is_complete = display_name.as_deref().is_some_and(|s| !s.is_empty())
        && birthdate.is_some()
        && gender.is_some()
        && !interested_in.is_empty();
    let profile_completed_at =
        current
            .profile_completed_at
            .or(if is_complete { Some(now) } else { None });

    sqlx::query(
        "UPDATE users SET
            display_name = $2,
            birthdate = $3,
            gender = $4,
            interested_in = $5,
            age_min = $6,
            age_max = $7,
            bio = $8,
            profile_completed_at = $9
         WHERE id = $1",
    )
    .bind(uid)
    .bind(&display_name)
    .bind(birthdate)
    .bind(&gender)
    .bind(&interested_in)
    .bind(age_min)
    .bind(age_max)
    .bind(&bio)
    .bind(profile_completed_at)
    .execute(&state.db)
    .await?;

    views::me_view(&state, uid).await.map(Json)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PhotoResponse {
    pub photo_url: String,
    pub photo_updated_at: chrono::DateTime<chrono::Utc>,
}

fn validate_jpeg_bytes(bytes: &[u8]) -> AppResult<()> {
    if bytes.is_empty() || bytes.len() > MAX_PHOTO_BYTES {
        return Err(AppError::validation("photo must be a JPEG under 600 KB"));
    }
    if bytes.len() < JPEG_MAGIC.len() || bytes[..JPEG_MAGIC.len()] != JPEG_MAGIC {
        return Err(AppError::validation("photo must be a JPEG"));
    }
    Ok(())
}

/// PUT /me/photo. Accepts either a raw `image/jpeg` body or a multipart body
/// with a `file` field (the `Content-Type` header decides which). Either way
/// the bytes must be a JPEG (`FF D8 FF` magic bytes) under 600 KB.
pub async fn put_photo(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    request: Request,
) -> AppResult<Json<PhotoResponse>> {
    let content_type = request
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    let photo: Vec<u8> = if content_type.starts_with("multipart/form-data") {
        let mut multipart = Multipart::from_request(request, &state)
            .await
            .map_err(|_| AppError::validation("invalid multipart body"))?;
        let mut file: Option<Bytes> = None;
        while let Some(field) = multipart
            .next_field()
            .await
            .map_err(|_| AppError::validation("invalid multipart body"))?
        {
            if field.name() == Some("file") {
                file = Some(
                    field
                        .bytes()
                        .await
                        .map_err(|_| AppError::validation("invalid multipart body"))?,
                );
            }
        }
        file.ok_or_else(|| AppError::validation("missing file field"))?
            .to_vec()
    } else {
        Bytes::from_request(request, &state)
            .await
            .map_err(|_| AppError::validation("invalid body"))?
            .to_vec()
    };

    validate_jpeg_bytes(&photo)?;

    let photo_updated_at: DateTime<Utc> = sqlx::query_scalar(
        "UPDATE users SET photo = $2, photo_updated_at = now()
         WHERE id = $1
         RETURNING photo_updated_at",
    )
    .bind(uid)
    .bind(&photo)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(PhotoResponse {
        photo_url: format!("/v1/users/{uid}/photo"),
        photo_updated_at,
    }))
}

/// DELETE /me/photo. `photo` and `photo_updated_at` are always cleared
/// together — `photo_updated_at.is_some()` is the sole "has a photo" signal
/// elsewhere (see `views::me_view`/`public_profile`).
pub async fn delete_photo(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<StatusCode> {
    sqlx::query("UPDATE users SET photo = NULL, photo_updated_at = NULL WHERE id = $1")
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /users/:id/photo (auth). 403s before revealing anything else if
/// either side has blocked the other.
///
/// Dates are anonymous, and the redacted `DateSession.partner` still carries
/// the partner's real user id (the client needs it for block/report), so this
/// endpoint must not hand a photo to just any signed-in caller with an id.
/// The photo is served only when the viewer is the target themselves or the
/// two have an *active* match (`matches` row with `unmatched_at IS NULL`,
/// the same rule `GET /matches` applies). Every other case, including a
/// target with no photo, is a plain 404 so the response never confirms that
/// a photo exists for an id the caller should not be looking at. The review
/// demo keeps working because `review::ensure_seeded_match` inserts an
/// active row between the first review phone and the demo account.
pub async fn get_user_photo(
    State(state): State<AppState>,
    AuthUser(viewer_id): AuthUser,
    Path(target_id): Path<Uuid>,
) -> AppResult<Response> {
    let blocked: bool = sqlx::query_scalar(
        "SELECT EXISTS (
            SELECT 1 FROM blocks
             WHERE (blocker_id = $1 AND blocked_id = $2)
                OR (blocker_id = $2 AND blocked_id = $1)
         )",
    )
    .bind(viewer_id)
    .bind(target_id)
    .fetch_one(&state.db)
    .await?;
    if blocked {
        return Err(AppError::Forbidden);
    }

    if viewer_id != target_id {
        let active_match: bool = sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT 1 FROM matches
                 WHERE unmatched_at IS NULL
                   AND ((user_a = $1 AND user_b = $2) OR (user_a = $2 AND user_b = $1))
             )",
        )
        .bind(viewer_id)
        .bind(target_id)
        .fetch_one(&state.db)
        .await?;
        if !active_match {
            return Err(AppError::NotFound);
        }
    }

    let row: Option<(Option<Vec<u8>>,)> = sqlx::query_as("SELECT photo FROM users WHERE id = $1")
        .bind(target_id)
        .fetch_optional(&state.db)
        .await?;

    let photo = row.and_then(|(p,)| p).ok_or(AppError::NotFound)?;

    Ok((
        [
            (CONTENT_TYPE, "image/jpeg"),
            (CACHE_CONTROL, "private, max-age=300"),
        ],
        photo,
    )
        .into_response())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LocationBody {
    pub lat: f64,
    pub lng: f64,
}

/// PUT /me/location. Stores the coarse (2-decimal, ~1km) location the privacy
/// copy promises, never the precise fix the client obtained.
pub async fn put_location(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
    Json(body): Json<LocationBody>,
) -> AppResult<StatusCode> {
    if !(-90.0..=90.0).contains(&body.lat) || !(-180.0..=180.0).contains(&body.lng) {
        return Err(AppError::validation(
            "lat must be -90..90 and lng must be -180..180",
        ));
    }
    let lat = (body.lat * 100.0).round() / 100.0;
    let lng = (body.lng * 100.0).round() / 100.0;

    sqlx::query("UPDATE users SET lat = $2, lng = $3, location_updated_at = now() WHERE id = $1")
        .bind(uid)
        .bind(lat)
        .bind(lng)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// DELETE /me. Every table that references `users` (dates, matches, messages,
/// blocks, reports, lobby, devices, push_subscriptions, refresh_tokens) does
/// so with `ON DELETE CASCADE`, so deleting this one row also revokes every
/// refresh token and removes every push subscription/device — no separate
/// cleanup queries needed.
pub async fn delete_me(
    State(state): State<AppState>,
    AuthUser(uid): AuthUser,
) -> AppResult<StatusCode> {
    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use chrono::{NaiveDate, TimeZone};

    use super::*;

    fn tz() -> Tz {
        chrono_tz::America::Los_Angeles
    }

    // ── displayName ──────────────────────────────────────────────────────

    #[test]
    fn display_name_trims_surrounding_whitespace() {
        assert_eq!(validate_display_name("  Maya  ").unwrap(), "Maya");
    }

    #[test]
    fn display_name_rejects_empty_after_trim() {
        assert!(validate_display_name("   ").is_err());
    }

    #[test]
    fn display_name_rejects_over_40_chars() {
        let name = "a".repeat(41);
        assert!(validate_display_name(&name).is_err());
    }

    #[test]
    fn display_name_accepts_exactly_40_chars() {
        let name = "a".repeat(40);
        assert!(validate_display_name(&name).is_ok());
    }

    #[test]
    fn display_name_rejects_control_characters() {
        // Embedded, not trailing, so `.trim()` can't strip them away first.
        assert!(validate_display_name("Ma\0ya").is_err());
        assert!(validate_display_name("Ma\nya").is_err());
        assert!(validate_display_name("Ma\tya").is_err());
    }

    // ── gender / interestedIn ────────────────────────────────────────────

    #[test]
    fn gender_accepts_the_three_allowed_values() {
        assert!(validate_gender("woman").is_ok());
        assert!(validate_gender("man").is_ok());
        assert!(validate_gender("nonbinary").is_ok());
    }

    #[test]
    fn gender_rejects_unknown_values() {
        assert!(validate_gender("other").is_err());
        assert!(validate_gender("").is_err());
    }

    #[test]
    fn interested_in_dedupes_and_preserves_order() {
        let out = validate_interested_in(vec![
            "man".to_string(),
            "woman".to_string(),
            "man".to_string(),
        ])
        .unwrap();
        assert_eq!(out, vec!["man".to_string(), "woman".to_string()]);
    }

    #[test]
    fn interested_in_rejects_empty() {
        assert!(validate_interested_in(vec![]).is_err());
    }

    #[test]
    fn interested_in_rejects_unknown_value() {
        assert!(validate_interested_in(vec!["robot".to_string()]).is_err());
    }

    // ── bio ──────────────────────────────────────────────────────────────

    #[test]
    fn bio_accepts_up_to_300_chars() {
        let bio = "a".repeat(300);
        assert!(validate_bio(&bio).is_ok());
    }

    #[test]
    fn bio_rejects_over_300_chars() {
        let bio = "a".repeat(301);
        assert!(validate_bio(&bio).is_err());
    }

    #[test]
    fn bio_trims_whitespace() {
        assert_eq!(validate_bio("  hi there  ").unwrap(), "hi there");
    }

    #[test]
    fn bio_allows_newline_and_tab() {
        assert!(validate_bio("line one\nline two\tindented").is_ok());
    }

    #[test]
    fn bio_rejects_other_control_characters() {
        assert!(validate_bio("hi\0there").is_err());
        assert!(validate_bio("hi\rthere").is_err());
    }

    // ── age range ────────────────────────────────────────────────────────

    #[test]
    fn age_range_accepts_the_full_span() {
        assert!(validate_age_range(18, 99).is_ok());
    }

    #[test]
    fn age_range_rejects_min_below_18() {
        assert!(validate_age_range(17, 99).is_err());
    }

    #[test]
    fn age_range_rejects_max_above_99() {
        assert!(validate_age_range(18, 100).is_err());
    }

    #[test]
    fn age_range_rejects_min_above_max() {
        assert!(validate_age_range(40, 30).is_err());
    }

    // ── birthdate -> age ─────────────────────────────────────────────────

    #[test]
    fn birthdate_accepts_exactly_18() {
        let birthdate = NaiveDate::from_ymd_opt(2008, 4, 2).unwrap();
        let now = chrono::Utc.with_ymd_and_hms(2026, 4, 2, 12, 0, 0).unwrap();
        assert!(validate_birthdate(birthdate, tz(), now).is_ok());
    }

    #[test]
    fn birthdate_rejects_one_day_short_of_18() {
        let birthdate = NaiveDate::from_ymd_opt(2008, 4, 2).unwrap();
        let now = chrono::Utc.with_ymd_and_hms(2026, 4, 1, 12, 0, 0).unwrap();
        assert!(validate_birthdate(birthdate, tz(), now).is_err());
    }

    #[test]
    fn birthdate_accepts_exactly_100() {
        let birthdate = NaiveDate::from_ymd_opt(1926, 4, 2).unwrap();
        let now = chrono::Utc.with_ymd_and_hms(2026, 4, 2, 12, 0, 0).unwrap();
        assert!(validate_birthdate(birthdate, tz(), now).is_ok());
    }

    #[test]
    fn birthdate_rejects_over_100() {
        let birthdate = NaiveDate::from_ymd_opt(1925, 4, 1).unwrap();
        let now = chrono::Utc.with_ymd_and_hms(2026, 4, 2, 12, 0, 0).unwrap();
        assert!(validate_birthdate(birthdate, tz(), now).is_err());
    }
}
