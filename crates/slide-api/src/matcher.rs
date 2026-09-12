//! The lobby matcher (SPEC.md section 1.6).
//!
//! Every tick (and once synchronously at the end of `POST /lobby/join`),
//! [`run_once`]:
//! 1. Deletes `lobby` rows with `heartbeat_at < now() - 20s`.
//! 2. Loads lobby users (joined with their profile/location/is_review_account)
//!    whose session is currently open, oldest `joined_at` first.
//! 3. Greedily pairs them ([`pair_greedy`]/[`compatible`]): mutual
//!    preference, mutual age range, within `MATCH_RADIUS_MILES`, no block
//!    either direction, no `dates` row between them tonight, no active
//!    `matches` row — except when both are review accounts, which bypasses
//!    preference/age/distance/"dated tonight" (blocks and active matches
//!    still apply).
//! 4. For each pair, in one transaction: inserts a `dates` row, deletes both
//!    `lobby` rows; after commit, mints each side's `DateSession` and
//!    publishes `date_matched` to each.
//!
//! The whole pass (steps 1-4) runs under a Postgres advisory transaction lock
//! (`pg_try_advisory_xact_lock`) so the background tick and a concurrent
//! `lobby_join`-triggered pass can't both pair the same user: whichever loses
//! the race just returns 0 pairs immediately rather than blocking, since the
//! other pass (or the next tick, 1.5s later) will make the same progress.

use std::{
    collections::{HashMap, HashSet},
    time::Duration,
};

use chrono::{DateTime, Utc};
use serde_json::json;
use uuid::Uuid;

use slide_core::{error::AppResult, models::DateRow};

use crate::{geo, session::SessionWindow, state::AppState, views};

/// Fixed key for the single matcher advisory lock. Arbitrary but stable
/// across processes (any i64 works; this one has no other significance).
const MATCHER_LOCK_KEY: i64 = 8_246_017_001;

/// One lobby member's matching-relevant profile, plus who they're already
/// blocked-by/dated-tonight-with/actively-matched-with within the current
/// candidate pool (scoped to just this pass, not global). Self-contained so
/// [`compatible`] needs no extra state.
#[derive(Debug, Clone)]
struct LobbyCandidate {
    user_id: Uuid,
    gender: String,
    interested_in: Vec<String>,
    age: i32,
    age_min: i16,
    age_max: i16,
    lat: Option<f64>,
    lng: Option<f64>,
    is_review_account: bool,
    blocked_with: HashSet<Uuid>,
    dated_today_with: HashSet<Uuid>,
    matched_with: HashSet<Uuid>,
}

/// All the matching rules, including the both-review-accounts bypass.
/// Blocks and active matches are never bypassed.
fn compatible(a: &LobbyCandidate, b: &LobbyCandidate, radius_miles: f64) -> bool {
    if a.blocked_with.contains(&b.user_id) || a.matched_with.contains(&b.user_id) {
        return false;
    }

    if a.is_review_account && b.is_review_account {
        return true;
    }

    if a.dated_today_with.contains(&b.user_id) {
        return false;
    }

    let mutual_preference = a.interested_in.iter().any(|g| g == &b.gender)
        && b.interested_in.iter().any(|g| g == &a.gender);
    if !mutual_preference {
        return false;
    }

    let age_ok = (b.age_min as i32..=b.age_max as i32).contains(&a.age)
        && (a.age_min as i32..=a.age_max as i32).contains(&b.age);
    if !age_ok {
        return false;
    }

    match (a.lat, a.lng, b.lat, b.lng) {
        (Some(alat), Some(alng), Some(blat), Some(blng)) => {
            geo::haversine_miles(alat, alng, blat, blng) <= radius_miles
        }
        _ => false,
    }
}

/// Greedily pair `candidates` (already ordered oldest-`joined_at`-first): for
/// each unpaired user in order, take the first later unpaired user they're
/// [`compatible`] with. Users with no compatible partner this pass are left
/// unpaired (they stay in the lobby for the next tick).
fn pair_greedy(candidates: &[LobbyCandidate], radius_miles: f64) -> Vec<(Uuid, Uuid)> {
    let mut paired = vec![false; candidates.len()];
    let mut pairs = Vec::new();
    for i in 0..candidates.len() {
        if paired[i] {
            continue;
        }
        for j in (i + 1)..candidates.len() {
            if paired[j] {
                continue;
            }
            if compatible(&candidates[i], &candidates[j], radius_miles) {
                paired[i] = true;
                paired[j] = true;
                pairs.push((candidates[i].user_id, candidates[j].user_id));
                break;
            }
        }
    }
    pairs
}

#[derive(Debug, sqlx::FromRow)]
struct LobbyRow {
    user_id: Uuid,
    birthdate: Option<chrono::NaiveDate>,
    gender: Option<String>,
    interested_in: Vec<String>,
    age_min: i16,
    age_max: i16,
    lat: Option<f64>,
    lng: Option<f64>,
    is_review_account: bool,
}

/// [`LobbyRow`] after resolving `age` from `birthdate` and filtering out rows
/// whose session isn't currently open — an intermediate step before building
/// [`LobbyCandidate`]s (which additionally need the relationship sets).
struct ProfileRow {
    user_id: Uuid,
    gender: String,
    interested_in: Vec<String>,
    age: i32,
    age_min: i16,
    age_max: i16,
    lat: Option<f64>,
    lng: Option<f64>,
    is_review_account: bool,
}

fn symmetric_pair_map(
    pairs: impl IntoIterator<Item = (Uuid, Uuid)>,
) -> HashMap<Uuid, HashSet<Uuid>> {
    let mut map: HashMap<Uuid, HashSet<Uuid>> = HashMap::new();
    for (x, y) in pairs {
        map.entry(x).or_default().insert(y);
        map.entry(y).or_default().insert(x);
    }
    map
}

/// One matching pass. Returns how many pairs were created (0 when the
/// advisory lock is already held by a concurrent pass, or when nobody
/// compatible is waiting).
pub async fn run_once(state: &AppState) -> AppResult<usize> {
    let mut tx = state.db.begin().await?;

    let locked: bool = sqlx::query_scalar("SELECT pg_try_advisory_xact_lock($1)")
        .bind(MATCHER_LOCK_KEY)
        .fetch_one(&mut *tx)
        .await?;
    if !locked {
        tx.rollback().await?;
        return Ok(0);
    }

    sqlx::query("DELETE FROM lobby WHERE heartbeat_at < now() - interval '20 seconds'")
        .execute(&mut *tx)
        .await?;

    let rows: Vec<LobbyRow> = sqlx::query_as(
        "SELECT l.user_id, u.birthdate, u.gender, u.interested_in, u.age_min, u.age_max,
                u.lat, u.lng, u.is_review_account
           FROM lobby l
           JOIN users u ON u.id = l.user_id
          ORDER BY l.joined_at ASC",
    )
    .fetch_all(&mut *tx)
    .await?;

    if rows.len() < 2 {
        tx.commit().await?;
        return Ok(0);
    }

    let now = Utc::now();
    let window = SessionWindow::compute(&state.cfg, now, false);
    let today = now.with_timezone(&state.cfg.session_tz).date_naive();

    let mut profiles: Vec<ProfileRow> = Vec::with_capacity(rows.len());
    for row in rows {
        let is_open = row.is_review_account || window.is_open;
        if !is_open {
            continue;
        }
        let (Some(birthdate), Some(gender)) = (row.birthdate, row.gender) else {
            tracing::warn!(user = %row.user_id, "matcher: lobby user missing birthdate/gender");
            continue;
        };
        let age = views::age_from_birthdate(birthdate, state.cfg.session_tz, now);
        profiles.push(ProfileRow {
            user_id: row.user_id,
            gender,
            interested_in: row.interested_in,
            age,
            age_min: row.age_min,
            age_max: row.age_max,
            lat: row.lat,
            lng: row.lng,
            is_review_account: row.is_review_account,
        });
    }

    if profiles.len() < 2 {
        tx.commit().await?;
        return Ok(0);
    }

    let ids: Vec<Uuid> = profiles.iter().map(|p| p.user_id).collect();

    let blocked_rows: Vec<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT blocker_id, blocked_id FROM blocks
          WHERE blocker_id = ANY($1) AND blocked_id = ANY($1)",
    )
    .bind(&ids)
    .fetch_all(&mut *tx)
    .await?;

    let dated_today_rows: Vec<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT user_a, user_b FROM dates
          WHERE session_date = $1 AND user_a = ANY($2) AND user_b = ANY($2)",
    )
    .bind(today)
    .bind(&ids)
    .fetch_all(&mut *tx)
    .await?;

    let matched_rows: Vec<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT user_a, user_b FROM matches
          WHERE unmatched_at IS NULL AND user_a = ANY($1) AND user_b = ANY($1)",
    )
    .bind(&ids)
    .fetch_all(&mut *tx)
    .await?;

    let blocked_map = symmetric_pair_map(blocked_rows);
    let dated_today_map = symmetric_pair_map(dated_today_rows);
    let matched_map = symmetric_pair_map(matched_rows);

    let candidates: Vec<LobbyCandidate> = profiles
        .into_iter()
        .map(|p| LobbyCandidate {
            blocked_with: blocked_map.get(&p.user_id).cloned().unwrap_or_default(),
            dated_today_with: dated_today_map.get(&p.user_id).cloned().unwrap_or_default(),
            matched_with: matched_map.get(&p.user_id).cloned().unwrap_or_default(),
            user_id: p.user_id,
            gender: p.gender,
            interested_in: p.interested_in,
            age: p.age,
            age_min: p.age_min,
            age_max: p.age_max,
            lat: p.lat,
            lng: p.lng,
            is_review_account: p.is_review_account,
        })
        .collect();

    let pairs = pair_greedy(&candidates, state.cfg.match_radius_miles);
    if pairs.is_empty() {
        tx.commit().await?;
        return Ok(0);
    }

    let mut inserted: Vec<DateRow> = Vec::with_capacity(pairs.len());
    for (a, b) in &pairs {
        let date_id = Uuid::new_v4();
        let ends_at: DateTime<Utc> = now + chrono::Duration::seconds(state.cfg.date_seconds);
        let date_row: DateRow = sqlx::query_as(
            "INSERT INTO dates (id, user_a, user_b, room_id, session_date, ends_at)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING *",
        )
        .bind(date_id)
        .bind(a)
        .bind(b)
        .bind(date_id.to_string())
        .bind(today)
        .bind(ends_at)
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query("DELETE FROM lobby WHERE user_id = ANY($1)")
            .bind(vec![*a, *b])
            .execute(&mut *tx)
            .await?;

        inserted.push(date_row);
    }

    tx.commit().await?;

    for date_row in &inserted {
        for uid in [date_row.user_a, date_row.user_b] {
            match views::date_session_for(state, date_row, uid).await {
                Ok(session) => {
                    state
                        .hub
                        .publish(uid, json!({ "type": "date_matched", "date": session }))
                        .await;
                }
                Err(error) => {
                    tracing::error!(%error, user = %uid, date = %date_row.id, "matcher: failed to mint date session for publish");
                }
            }
        }
    }

    Ok(inserted.len())
}

/// Background task: ticks `run_once` every 1.5s. Spawned once from `main`.
/// Logs (never panics on) a failed pass so one bad tick can't kill the loop.
pub async fn run(state: AppState) {
    let mut ticker = tokio::time::interval(Duration::from_millis(1500));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        ticker.tick().await;
        if let Err(error) = run_once(&state).await {
            tracing::error!(%error, "matcher pass failed");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[allow(clippy::too_many_arguments)]
    fn candidate(
        gender: &str,
        interested_in: &[&str],
        age: i32,
        age_min: i16,
        age_max: i16,
        lat: f64,
        lng: f64,
        is_review_account: bool,
    ) -> LobbyCandidate {
        LobbyCandidate {
            user_id: Uuid::new_v4(),
            gender: gender.to_string(),
            interested_in: interested_in.iter().map(|s| s.to_string()).collect(),
            age,
            age_min,
            age_max,
            lat: Some(lat),
            lng: Some(lng),
            is_review_account,
            blocked_with: HashSet::new(),
            dated_today_with: HashSet::new(),
            matched_with: HashSet::new(),
        }
    }

    // San Francisco-ish and LA-ish coordinates for the distance tests.
    const SF: (f64, f64) = (37.7749, -122.4194);
    const LA: (f64, f64) = (34.0537, -118.2428);

    #[test]
    fn compatible_pair_matches() {
        let a = candidate("woman", &["man"], 30, 25, 40, SF.0, SF.1, false);
        let b = candidate("man", &["woman"], 32, 28, 38, SF.0, SF.1, false);
        assert!(compatible(&a, &b, 75.0));
        assert!(compatible(&b, &a, 75.0));
    }

    #[test]
    fn one_sided_preference_is_incompatible() {
        let a = candidate("woman", &["man"], 30, 25, 40, SF.0, SF.1, false);
        // b is interested in women, not men, so the preference isn't mutual.
        let b = candidate("man", &["woman"], 30, 25, 40, SF.0, SF.1, false);
        let c = candidate("man", &["man"], 30, 25, 40, SF.0, SF.1, false);
        assert!(compatible(&a, &b, 75.0));
        assert!(!compatible(&a, &c, 75.0));
    }

    #[test]
    fn outside_either_ones_age_range_is_incompatible() {
        let a = candidate("woman", &["man"], 45, 25, 50, SF.0, SF.1, false);
        let b = candidate("man", &["woman"], 30, 28, 38, SF.0, SF.1, false);
        // a (45) is outside b's 28..38 range.
        assert!(!compatible(&a, &b, 75.0));
    }

    #[test]
    fn beyond_radius_is_incompatible() {
        let a = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let b = candidate("man", &["woman"], 30, 18, 99, LA.0, LA.1, false);
        assert!(!compatible(&a, &b, 75.0));
        assert!(compatible(&a, &b, 400.0));
    }

    #[test]
    fn missing_location_is_incompatible() {
        let a = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let mut b = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, false);
        b.lat = None;
        assert!(!compatible(&a, &b, 75.0));
    }

    #[test]
    fn a_block_either_direction_is_incompatible_even_for_review_accounts() {
        let mut a = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, true);
        let b = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, true);
        a.blocked_with.insert(b.user_id);
        assert!(!compatible(&a, &b, 75.0));
        // Direction matters only for lookup, not semantics: from b's own set
        // (not populated here) b would need its own entry — this asserts a's
        // check alone already blocks the pairing from a's side.
    }

    #[test]
    fn an_active_match_is_incompatible_even_for_review_accounts() {
        let mut a = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, true);
        let b = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, true);
        a.matched_with.insert(b.user_id);
        assert!(!compatible(&a, &b, 75.0));
    }

    #[test]
    fn dated_today_blocks_a_rematch_for_normal_accounts() {
        let mut a = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let b = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, false);
        a.dated_today_with.insert(b.user_id);
        assert!(!compatible(&a, &b, 75.0));
    }

    #[test]
    fn two_review_accounts_bypass_preference_age_distance_and_dated_today() {
        let mut a = candidate("woman", &["woman"], 60, 18, 20, SF.0, SF.1, true);
        let mut b = candidate("man", &["man"], 22, 40, 45, LA.0, LA.1, true);
        a.dated_today_with.insert(b.user_id);
        b.dated_today_with.insert(a.user_id);
        // Wildly incompatible on preference/age/distance and dated tonight,
        // but both are review accounts, so it's fine.
        assert!(compatible(&a, &b, 75.0));
        assert!(compatible(&b, &a, 75.0));
    }

    #[test]
    fn one_review_account_does_not_get_the_bypass() {
        let a = candidate("woman", &["woman"], 60, 18, 20, SF.0, SF.1, true);
        let b = candidate("man", &["man"], 22, 40, 45, SF.0, SF.1, false);
        assert!(!compatible(&a, &b, 75.0));
    }

    #[test]
    fn pair_greedy_pairs_oldest_first_and_skips_incompatible() {
        // Order matters: candidates are passed in joined_at order.
        let a = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let unmatched_woman = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let b = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, false);
        let ids = (a.user_id, unmatched_woman.user_id, b.user_id);
        let pairs = pair_greedy(&[a, unmatched_woman, b], 75.0);
        assert_eq!(pairs, vec![(ids.0, ids.2)]);
    }

    #[test]
    fn pair_greedy_leaves_an_odd_one_out_unpaired() {
        let a = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let b = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, false);
        let c = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, false);
        let pairs = pair_greedy(&[a, b, c], 75.0);
        assert_eq!(pairs.len(), 1);
    }

    #[test]
    fn pair_greedy_pairs_every_compatible_couple_in_a_larger_pool() {
        let a1 = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let m1 = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, false);
        let a2 = candidate("woman", &["man"], 30, 18, 99, SF.0, SF.1, false);
        let m2 = candidate("man", &["woman"], 30, 18, 99, SF.0, SF.1, false);
        let pairs = pair_greedy(&[a1, m1, a2, m2], 75.0);
        assert_eq!(pairs.len(), 2);
    }
}
