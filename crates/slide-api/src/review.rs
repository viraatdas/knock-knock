//! App Review fixtures (SPEC.md section 1.10).
//!
//! App Review must be able to test the app outside the 7-8 PM PT window and
//! on a single device. `routes::auth::issue_session_for_phone` calls
//! [`ensure_fixtures`] for every login from a `REVIEW_PHONES` number.
//!
//! [`SessionWindow::compute`](crate::session::SessionWindow::compute) and the
//! matcher (SPEC 1.6) already special-case `is_review_account` — nothing else
//! needs to change here for that part of the deal.

use chrono::{Duration, NaiveDate, Utc};
use uuid::Uuid;

use slide_core::{
    error::AppResult,
    models::{User, USER_COLUMNS},
};

use crate::{state::AppState, views};

const REVIEW_BIO: &str = "Here to try the app.";
const REVIEW_LAT: f64 = 37.77;
const REVIEW_LNG: f64 = -122.42;

const SAM_BIO: &str = "Coffee, long walks, bad puns.";
const SAM_LAT: f64 = 37.78;
const SAM_LNG: f64 = -122.41;

fn all_genders() -> Vec<String> {
    ["woman", "man", "nonbinary"]
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// See the module doc comment. Safe to call on every login: every step below
/// is idempotent, and only the newly-created-match branch has a one-time
/// side effect (seeding Sam's three messages).
pub async fn ensure_fixtures(state: &AppState, user: &User) -> AppResult<()> {
    if !user.is_review_account {
        sqlx::query("UPDATE users SET is_review_account = true WHERE id = $1")
            .bind(user.id)
            .execute(&state.db)
            .await?;
    }

    if !views::profile_is_complete(user) {
        fill_review_profile(state, user).await?;
    }

    let sam_id = ensure_demo_user(state).await?;

    let is_first_review_phone = state
        .cfg
        .review_phones
        .first()
        .is_some_and(|p| p == &user.phone);
    if is_first_review_phone {
        ensure_seeded_match(state, user.id, sam_id).await?;
    }

    Ok(())
}

/// Fill in a review account's profile with fixture data. Gender is "woman"
/// for `REVIEW_PHONES[0]` and "man" for every other configured review phone
/// (only two are used in practice — see SPEC.md section 6).
async fn fill_review_profile(state: &AppState, user: &User) -> AppResult<()> {
    let is_first = state
        .cfg
        .review_phones
        .first()
        .is_some_and(|p| p == &user.phone);
    let gender = if is_first { "woman" } else { "man" };
    let birthdate = NaiveDate::from_ymd_opt(1994, 6, 1).expect("1994-06-01 is a valid date");
    let now = Utc::now();

    sqlx::query(
        "UPDATE users SET
             display_name = 'Reviewer',
             birthdate = $2,
             gender = $3,
             interested_in = $4,
             age_min = 18,
             age_max = 99,
             bio = $5,
             lat = $6,
             lng = $7,
             location_updated_at = $8,
             profile_completed_at = COALESCE(profile_completed_at, $8)
         WHERE id = $1",
    )
    .bind(user.id)
    .bind(birthdate)
    .bind(gender)
    .bind(all_genders())
    .bind(REVIEW_BIO)
    .bind(REVIEW_LAT)
    .bind(REVIEW_LNG)
    .bind(now)
    .execute(&state.db)
    .await?;

    Ok(())
}

/// Ensure the demo user (`cfg.review_demo_phone`, "Sam") exists with a
/// complete, review-account profile. Returns Sam's user id either way. The
/// upsert only ever touches `is_review_account` on an existing row so a
/// tester who has since edited Sam's profile through the app isn't clobbered
/// on the next login.
async fn ensure_demo_user(state: &AppState) -> AppResult<Uuid> {
    let birthdate = NaiveDate::from_ymd_opt(1995, 3, 14).expect("1995-03-14 is a valid date");
    let now = Utc::now();

    let insert_sql = format!(
        "INSERT INTO users (
             phone, display_name, birthdate, gender, interested_in, age_min, age_max, bio,
             lat, lng, location_updated_at, is_review_account, profile_completed_at
         ) VALUES ($1, 'Sam', $2, 'nonbinary', $3, 18, 99, $4, $5, $6, $7, true, $7)
         ON CONFLICT (phone) DO UPDATE SET is_review_account = true
         RETURNING {USER_COLUMNS}"
    );
    let sam: User = sqlx::query_as(&insert_sql)
        .bind(&state.cfg.review_demo_phone)
        .bind(birthdate)
        .bind(all_genders())
        .bind(SAM_BIO)
        .bind(SAM_LAT)
        .bind(SAM_LNG)
        .bind(now)
        .fetch_one(&state.db)
        .await?;

    Ok(sam.id)
}

/// Ensure a `matches` row between `reviewer_id` and `sam_id` exists, seeding
/// the three fixture messages only when that row is newly created. A
/// pre-existing row (active or previously unmatched by the tester) is left
/// untouched — unmatching Sam is a real action a reviewer might be testing,
/// and this must not undo it on the next login.
async fn ensure_seeded_match(state: &AppState, reviewer_id: Uuid, sam_id: Uuid) -> AppResult<()> {
    let (user_a, user_b) = if reviewer_id < sam_id {
        (reviewer_id, sam_id)
    } else {
        (sam_id, reviewer_id)
    };

    let match_id: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO matches (user_a, user_b) VALUES ($1, $2)
         ON CONFLICT (user_a, user_b) DO NOTHING
         RETURNING id",
    )
    .bind(user_a)
    .bind(user_b)
    .fetch_optional(&state.db)
    .await?;

    let Some(match_id) = match_id else {
        return Ok(());
    };

    // Explicit, increasing timestamps so the seeded messages always read in
    // the right order regardless of clock resolution.
    let now = Utc::now();
    let messages = [
        (sam_id, "Hey! That was fun.", now),
        (
            reviewer_id,
            "Same. You had me at the pun.",
            now + Duration::seconds(30),
        ),
        (sam_id, "Careful, I have more.", now + Duration::seconds(60)),
    ];
    for (sender_id, body, created_at) in messages {
        sqlx::query(
            "INSERT INTO messages (match_id, sender_id, body, created_at)
             VALUES ($1, $2, $3, $4)",
        )
        .bind(match_id)
        .bind(sender_id)
        .bind(body)
        .bind(created_at)
        .execute(&state.db)
        .await?;
    }

    Ok(())
}
