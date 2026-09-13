//! Shared, fully-implemented response shapes for the speed-date API.
//!
//! Every route file builds its JSON responses out of these structs and
//! helpers instead of re-deriving age/distance/profile-completeness math or
//! re-minting LiveKit tokens inline. Field names are camelCase to match the
//! wire contract in SPEC.md sections 1.5-1.7 exactly.
//!
//! Dates are anonymous: a `DateSession` never carries the partner's identity
//! (see [`PublicProfile::redacted`] and [`date_session_for`]). The real
//! profile only ever travels inside a `MatchSummary`, which exists only after
//! a mutual yes.

use chrono::{DateTime, Datelike, NaiveDate, Utc};
use chrono_tz::Tz;
use serde::Serialize;
use uuid::Uuid;

use slide_core::{
    error::{AppError, AppResult},
    models::{DateRow, MatchRow, User, USER_COLUMNS},
};

use crate::{geo, livekit, state::AppState};

// ── View structs ─────────────────────────────────────────────────────────────

/// The `displayName` on a redacted date partner. Reads as a name wherever the
/// client interpolates one ("Keep talking with your date?").
pub const REDACTED_DISPLAY_NAME: &str = "your date";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PublicProfile {
    pub id: Uuid,
    pub display_name: String,
    /// `None` on a redacted date partner (and, defensively, for a target
    /// with no birthdate). The iOS model decodes this as `Int?`.
    pub age: Option<i32>,
    /// `woman` | `man` | `nonbinary`, or `None` on a redacted date partner.
    /// The shipped 1.1.0 client decodes this as an optional `Gender` enum:
    /// `null` decodes, an empty string does not (it fails the whole
    /// `DateSession`), so this must never be serialized as `""`.
    pub gender: Option<String>,
    pub bio: String,
    pub has_photo: bool,
    pub photo_url: Option<String>,
    /// Rounded to the nearest mile; `None` when either side has no location.
    pub distance_miles: Option<i32>,
}

impl PublicProfile {
    /// The partner card handed out *during* a date: only the id survives, so
    /// the client can key mock video / block-and-report on it, and every
    /// identity field is empty. The field set and shape stay identical to a
    /// real card so the 1.1.0 client already in the App Store keeps decoding
    /// `DateSession.partner` unchanged; it just has nothing to show.
    ///
    /// Two fields are chosen for that client specifically: `gender` is
    /// `None` (it decodes an optional enum, so `""` would break every date)
    /// and `display_name` is the placeholder "your date", because the 1.1.0
    /// decision screen interpolates the name into "Keep talking with
    /// \(name)?" and has no fallback for an empty one.
    pub fn redacted(id: Uuid) -> Self {
        Self {
            id,
            display_name: REDACTED_DISPLAY_NAME.to_string(),
            age: None,
            gender: None,
            bio: String::new(),
            has_photo: false,
            photo_url: None,
            distance_miles: None,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MeView {
    pub id: Uuid,
    pub phone: String,
    pub display_name: Option<String>,
    pub birthdate: Option<NaiveDate>,
    pub age: Option<i32>,
    pub gender: Option<String>,
    pub interested_in: Vec<String>,
    pub age_min: i16,
    pub age_max: i16,
    pub bio: String,
    pub has_photo: bool,
    pub photo_url: Option<String>,
    pub photo_updated_at: Option<DateTime<Utc>>,
    pub profile_complete: bool,
    pub has_location: bool,
    pub is_review_account: bool,
    pub created_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DateSession {
    pub id: Uuid,
    pub room_id: String,
    pub sfu_url: String,
    pub join_token: String,
    pub started_at: DateTime<Utc>,
    pub ends_at: DateTime<Utc>,
    pub date_seconds: i64,
    pub partner: PublicProfile,
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct LastMessage {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub body: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MatchSummary {
    pub id: Uuid,
    pub partner: PublicProfile,
    pub created_at: DateTime<Utc>,
    pub last_message: Option<LastMessage>,
    pub unread_count: i64,
}

/// The wire shape SPEC.md calls `Message`; named `MessageView` here to match
/// this crate's `routes::chat` naming (avoids a clash with a future DB-facing
/// `Message` type). Field-for-field identical to the spec's `Message` object.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct MessageView {
    pub id: Uuid,
    pub match_id: Uuid,
    pub sender_id: Uuid,
    pub body: String,
    pub created_at: DateTime<Utc>,
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Age in whole years as of `now`, computed on the calendar date in `tz` (so a
/// birthday at 11 PM PT on the day itself already counts).
pub fn age_from_birthdate(birthdate: NaiveDate, tz: Tz, now: DateTime<Utc>) -> i32 {
    let today = now.with_timezone(&tz).date_naive();
    let mut age = today.year() - birthdate.year();
    let had_birthday_this_year =
        (today.month(), today.day()) >= (birthdate.month(), birthdate.day());
    if !had_birthday_this_year {
        age -= 1;
    }
    age
}

async fn fetch_user(state: &AppState, id: Uuid) -> AppResult<User> {
    let sql = format!("SELECT {USER_COLUMNS} FROM users WHERE id = $1");
    sqlx::query_as::<_, User>(&sql)
        .bind(id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)
}

/// Turns "no such user" into 401 for a lookup keyed on the caller's own
/// access-token subject (as opposed to a path-parameter target id, which
/// should stay a plain 404). Shared by every route module that re-fetches
/// its own `fetch_user`-shaped copy for `uid` from `AuthUser`.
pub fn self_or_unauthorized<T>(result: AppResult<T>) -> AppResult<T> {
    result.map_err(|e| match e {
        AppError::NotFound => AppError::Unauthorized,
        other => other,
    })
}

fn photo_url_for(has_photo: bool, user_id: Uuid) -> Option<String> {
    has_photo.then(|| format!("/v1/users/{user_id}/photo"))
}

/// True when the four profile-completion fields (SPEC 1.5: displayName,
/// birthdate, gender, interestedIn) are all present. Added for
/// `review::ensure_fixtures`, which needs this same predicate outside a
/// `MeView` to decide whether a review account's profile needs seeding;
/// `me_view` below has its own inline copy that predates this helper.
pub fn profile_is_complete(user: &User) -> bool {
    user.display_name
        .as_deref()
        .is_some_and(|s| !s.trim().is_empty())
        && user.birthdate.is_some()
        && user.gender.is_some()
        && !user.interested_in.is_empty()
}

/// `GET /me`. Derives `profileComplete` fresh from the required fields rather
/// than trusting the once-set `profile_completed_at` column. `uid` always
/// comes from the caller's own access token, so a missing row means the
/// account behind that token no longer exists (deleted) — reported as 401,
/// not 404, since a stale token isn't "not found", it's no longer valid.
pub async fn me_view(state: &AppState, uid: Uuid) -> AppResult<MeView> {
    let user = self_or_unauthorized(fetch_user(state, uid).await)?;
    let now = Utc::now();
    let age = user
        .birthdate
        .map(|b| age_from_birthdate(b, state.cfg.session_tz, now));
    let has_photo = user.photo_updated_at.is_some();
    let display_name_present = user
        .display_name
        .as_deref()
        .is_some_and(|s| !s.trim().is_empty());
    let profile_complete = display_name_present
        && user.birthdate.is_some()
        && user.gender.is_some()
        && !user.interested_in.is_empty();

    Ok(MeView {
        id: user.id,
        phone: user.phone,
        display_name: user.display_name,
        birthdate: user.birthdate,
        age,
        gender: user.gender,
        interested_in: user.interested_in,
        age_min: user.age_min,
        age_max: user.age_max,
        bio: user.bio,
        has_photo,
        photo_url: photo_url_for(has_photo, user.id),
        photo_updated_at: user.photo_updated_at,
        profile_complete,
        has_location: user.lat.is_some() && user.lng.is_some(),
        is_review_account: user.is_review_account,
        created_at: user.created_at,
        last_seen_at: user.last_seen_at,
    })
}

/// `target`'s public-facing card as seen by `viewer` (distance is relative to
/// the viewer's own coarse location). A target with no birthdate (should not
/// happen once profileComplete is required to appear anywhere) reports
/// `age: null` rather than failing the whole response.
///
/// This is the *revealed* card: matches, chat, and the nightly recap. A live
/// date never uses it; `date_session_for` hands out
/// [`PublicProfile::redacted`] instead.
pub async fn public_profile(
    state: &AppState,
    viewer_id: Uuid,
    target_id: Uuid,
) -> AppResult<PublicProfile> {
    let viewer = fetch_user(state, viewer_id).await?;
    let target = fetch_user(state, target_id).await?;
    let now = Utc::now();

    let age = match target.birthdate {
        Some(b) => Some(age_from_birthdate(b, state.cfg.session_tz, now)),
        None => {
            tracing::warn!(user = %target.id, "public_profile: target has no birthdate");
            None
        }
    };
    let has_photo = target.photo_updated_at.is_some();
    let distance_miles = match (viewer.lat, viewer.lng, target.lat, target.lng) {
        (Some(vlat), Some(vlng), Some(tlat), Some(tlng)) => {
            Some(geo::haversine_miles(vlat, vlng, tlat, tlng).round() as i32)
        }
        _ => None,
    };

    Ok(PublicProfile {
        id: target.id,
        display_name: target.display_name.unwrap_or_default(),
        age,
        gender: target.gender,
        bio: target.bio,
        has_photo,
        photo_url: photo_url_for(has_photo, target.id),
        distance_miles,
    })
}

/// Build the `DateSession` handed to `recipient_id` for `date_row`: the
/// partner is the *other* participant, the LiveKit token is minted for
/// `recipient_id`. Returns 503 `unavailable` if LiveKit isn't configured.
///
/// The date is anonymous. `partner` is [`PublicProfile::redacted`] (id plus
/// the "your date" placeholder name, every other identity field empty) and
/// the LiveKit token carries no display name, so neither the API payload nor
/// the room's participant metadata can tell the other side who they're
/// talking to. Identity is revealed only by the `MatchSummary` a mutual yes
/// produces (see [`match_summary`]).
pub async fn date_session_for(
    state: &AppState,
    date_row: &DateRow,
    recipient_id: Uuid,
) -> AppResult<DateSession> {
    let partner_id = if date_row.user_a == recipient_id {
        date_row.user_b
    } else {
        date_row.user_a
    };

    if state.cfg.livekit_url.is_empty()
        || state.cfg.livekit_api_key.is_empty()
        || state.cfg.livekit_api_secret.is_empty()
    {
        return Err(AppError::unavailable("livekit is not configured"));
    }

    let partner = PublicProfile::redacted(partner_id);

    let ttl = state.cfg.date_seconds + 120;
    let join_token = livekit::mint_token(
        &state.cfg.livekit_api_key,
        &state.cfg.livekit_api_secret,
        &recipient_id.to_string(),
        None,
        &date_row.room_id,
        ttl,
    )
    .map_err(|e| AppError::Internal(anyhow::Error::new(e)))?;

    Ok(DateSession {
        id: date_row.id,
        room_id: date_row.room_id.clone(),
        sfu_url: state.cfg.livekit_url.clone(),
        join_token,
        started_at: date_row.started_at,
        ends_at: date_row.ends_at,
        date_seconds: state.cfg.date_seconds,
        partner,
    })
}

/// Build a `MatchSummary` for `viewer_id`'s side of `match_row`.
pub async fn match_summary(
    state: &AppState,
    match_row: &MatchRow,
    viewer_id: Uuid,
) -> AppResult<MatchSummary> {
    let partner_id = if match_row.user_a == viewer_id {
        match_row.user_b
    } else {
        match_row.user_a
    };
    let partner = public_profile(state, viewer_id, partner_id).await?;

    let last_message: Option<LastMessage> = sqlx::query_as(
        "SELECT id, sender_id, body, created_at
           FROM messages
          WHERE match_id = $1
          ORDER BY created_at DESC
          LIMIT 1",
    )
    .bind(match_row.id)
    .fetch_optional(&state.db)
    .await?;

    let last_read_at: Option<DateTime<Utc>> = sqlx::query_scalar(
        "SELECT last_read_at FROM match_reads WHERE match_id = $1 AND user_id = $2",
    )
    .bind(match_row.id)
    .bind(viewer_id)
    .fetch_optional(&state.db)
    .await?;

    let unread_count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM messages
          WHERE match_id = $1
            AND sender_id = $2
            AND ($3::timestamptz IS NULL OR created_at > $3)",
    )
    .bind(match_row.id)
    .bind(partner_id)
    .bind(last_read_at)
    .fetch_one(&state.db)
    .await?;

    Ok(MatchSummary {
        id: match_row.id,
        partner,
        created_at: match_row.created_at,
        last_message,
        unread_count,
    })
}

#[cfg(test)]
mod tests {
    use chrono::{NaiveDate, TimeZone};
    use uuid::Uuid;

    use super::{age_from_birthdate, PublicProfile, REDACTED_DISPLAY_NAME};

    /// A fully populated card, the shape a match or chat hands out. The
    /// redaction tests compare against it so the two can never drift apart.
    fn real_card(id: Uuid) -> PublicProfile {
        PublicProfile {
            id,
            display_name: "Maya".to_string(),
            age: Some(30),
            gender: Some("woman".to_string()),
            bio: "Coffee and long walks.".to_string(),
            has_photo: true,
            photo_url: Some(format!("/v1/users/{id}/photo")),
            distance_miles: Some(12),
        }
    }

    fn sorted_keys(value: &serde_json::Value) -> Vec<String> {
        let mut keys: Vec<String> = value.as_object().unwrap().keys().cloned().collect();
        keys.sort_unstable();
        keys
    }

    #[test]
    fn redacted_profile_keeps_only_the_id() {
        let id = Uuid::new_v4();
        let profile = PublicProfile::redacted(id);

        assert_eq!(profile.id, id);
        assert_eq!(profile.display_name, "your date");
        assert_eq!(profile.display_name, REDACTED_DISPLAY_NAME);
        assert_eq!(profile.age, None);
        assert_eq!(profile.gender, None);
        assert_eq!(profile.bio, "");
        assert!(!profile.has_photo);
        assert_eq!(profile.photo_url, None);
        assert_eq!(profile.distance_miles, None);
    }

    /// Locks the wire shape: the 1.1.0 client decodes every key of a real
    /// card, so the redacted card must carry exactly the same key set, and
    /// nothing but `id` and the placeholder name may carry a value. `gender`
    /// in particular must be `null`, not `""`: the client decodes it as an
    /// optional enum and an empty string fails the whole `DateSession`.
    #[test]
    fn redacted_profile_serializes_with_no_identity_on_the_wire() {
        let id = Uuid::new_v4();
        let json = serde_json::to_value(PublicProfile::redacted(id)).unwrap();
        let real = serde_json::to_value(real_card(id)).unwrap();
        assert_eq!(sorted_keys(&json), sorted_keys(&real));

        let object = json.as_object().unwrap();
        assert_eq!(object["id"], serde_json::json!(id.to_string()));
        assert_eq!(object["displayName"], serde_json::json!("your date"));
        assert_eq!(object["bio"], serde_json::json!(""));
        assert!(object["gender"].is_null(), "gender must be null, not \"\"");
        for key in ["age", "photoUrl", "distanceMiles"] {
            assert!(object[key].is_null(), "{key} leaked");
        }
        assert_eq!(object["hasPhoto"], serde_json::json!(false));
    }

    #[test]
    fn age_counts_a_same_day_birthday_as_already_had() {
        let tz = chrono_tz::America::Los_Angeles;
        let birthdate = NaiveDate::from_ymd_opt(1996, 4, 2).unwrap();
        let now = chrono::Utc.with_ymd_and_hms(2026, 4, 2, 23, 0, 0).unwrap();
        assert_eq!(age_from_birthdate(birthdate, tz, now), 30);
    }

    #[test]
    fn age_is_one_less_the_day_before_the_birthday() {
        let tz = chrono_tz::America::Los_Angeles;
        let birthdate = NaiveDate::from_ymd_opt(1996, 4, 2).unwrap();
        let now = chrono::Utc.with_ymd_and_hms(2026, 4, 1, 12, 0, 0).unwrap();
        assert_eq!(age_from_birthdate(birthdate, tz, now), 29);
    }
}
