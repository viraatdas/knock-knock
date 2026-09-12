//! The daily "doors are open" push (SPEC.md section 1.11).
//!
//! Every 30s: compute local time in `cfg.session_tz`. If it falls within
//! `[open, open + 5 minutes)` and a Redis `SET NX` on
//! `push:doors:<session_date>` succeeds (so only one tick, across however
//! many API instances are running, ever fires it per night), send an APNs
//! alert to every user with a complete profile and an `apns` subscription.

use std::time::Duration as StdDuration;

use chrono::{DateTime, Duration, NaiveDate, TimeZone, Utc};
use redis::{AsyncCommands, ExistenceCheck, SetExpiry, SetOptions};
use uuid::Uuid;

use crate::{config::Config, state::AppState};

/// How long the door's-open guard key sticks around in Redis. Longer than the
/// 5-minute firing window (so a slow tick can't slip through twice) but short
/// enough not to accumulate keys forever — one per session date.
const DOORS_GUARD_TTL_SECS: u64 = 6 * 60 * 60;
const DOORS_OPEN_WINDOW: Duration = Duration::minutes(5);

/// Background task: ticks every 30s. Spawned once from `main`. Never panics —
/// every fallible step is logged and skipped rather than propagated.
pub async fn run(state: AppState) {
    let mut ticker = tokio::time::interval(StdDuration::from_secs(30));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        ticker.tick().await;
        if let Err(error) = tick_once(&state).await {
            tracing::warn!(%error, "scheduler: doors-open tick failed");
        }
    }
}

/// True when `now`, read in `cfg.session_tz`, falls within the 5-minute
/// window starting at tonight's doors-open time (`SESSION_OPEN_HOUR:MINUTE`).
/// Deliberately ignores `SESSION_ALWAYS_OPEN`/review overrides: this drives a
/// once-a-night broadcast tied to the real wall clock, not the per-user
/// session-testing escape hatches in `session.rs`.
fn is_doors_open_window(cfg: &Config, now: DateTime<Utc>) -> bool {
    let local = now.with_timezone(&cfg.session_tz);
    let today = local.date_naive();
    let Some(open) = local_open_time(cfg, today) else {
        return false;
    };
    local >= open && local < open + DOORS_OPEN_WINDOW
}

/// Resolve `date` at the configured open hour/minute to a concrete instant in
/// `cfg.session_tz`. `None` only on the (never-hit-at-7PM) DST spring-forward
/// gap, which this task simply skips a tick for rather than guessing.
fn local_open_time(cfg: &Config, date: NaiveDate) -> Option<DateTime<chrono_tz::Tz>> {
    let naive = date.and_hms_opt(cfg.session_open_hour, cfg.session_open_minute, 0)?;
    match cfg.session_tz.from_local_datetime(&naive) {
        chrono::LocalResult::Single(dt) => Some(dt),
        chrono::LocalResult::Ambiguous(earlier, _later) => Some(earlier),
        chrono::LocalResult::None => None,
    }
}

async fn tick_once(state: &AppState) -> anyhow::Result<()> {
    let now = Utc::now();
    if !is_doors_open_window(&state.cfg, now) {
        return Ok(());
    }

    let session_date = now.with_timezone(&state.cfg.session_tz).date_naive();
    let key = format!("push:doors:{session_date}");

    let mut conn = state.redis.clone();
    let acquired: bool = conn
        .set_options(
            &key,
            "1",
            SetOptions::default()
                .conditional_set(ExistenceCheck::NX)
                .with_expiration(SetExpiry::EX(DOORS_GUARD_TTL_SECS)),
        )
        .await?;
    if !acquired {
        // Another tick (this instance or another) already fired tonight.
        return Ok(());
    }

    let recipients: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT DISTINCT u.id
           FROM users u
           JOIN push_subscriptions ps ON ps.user_id = u.id AND ps.kind = 'apns'
          WHERE u.profile_completed_at IS NOT NULL",
    )
    .fetch_all(&state.db)
    .await?;

    for (user_id,) in &recipients {
        let mut data = serde_json::Map::new();
        data.insert("type".to_string(), serde_json::json!("doors_open"));
        state
            .push
            .notify_alert(
                &state.db,
                *user_id,
                "Knock Knock",
                "Doors are open. Speed dates until 8.",
                Some("doors-open"),
                Some("knock.caf"),
                3600,
                Some(data),
            )
            .await;
    }

    tracing::info!(count = recipients.len(), %session_date, "scheduler: sent doors-open push");
    Ok(())
}

#[cfg(test)]
mod tests {
    use chrono_tz::America::Los_Angeles;

    use super::*;

    fn cfg() -> Config {
        Config {
            session_always_open: false,
            ..Config::from_env()
        }
    }

    fn pt(date: NaiveDate, hour: u32, minute: u32, second: u32) -> DateTime<Utc> {
        let naive = date.and_hms_opt(hour, minute, second).unwrap();
        Los_Angeles
            .from_local_datetime(&naive)
            .single()
            .expect("unambiguous PT time")
            .with_timezone(&Utc)
    }

    #[test]
    fn closed_one_second_before_the_window_opens() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        assert!(!is_doors_open_window(&cfg, pt(today, 18, 59, 59)));
    }

    #[test]
    fn open_at_the_opening_second() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        assert!(is_doors_open_window(&cfg, pt(today, 19, 0, 0)));
    }

    #[test]
    fn still_open_a_few_minutes_in() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        assert!(is_doors_open_window(&cfg, pt(today, 19, 4, 59)));
    }

    #[test]
    fn closed_once_five_minutes_have_passed() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        assert!(!is_doors_open_window(&cfg, pt(today, 19, 5, 0)));
    }

    #[test]
    fn closed_the_rest_of_the_night() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        assert!(!is_doors_open_window(&cfg, pt(today, 19, 59, 59)));
        assert!(!is_doors_open_window(&cfg, pt(today, 23, 0, 0)));
    }

    #[test]
    fn closed_before_the_window_the_next_morning() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 16).unwrap();
        assert!(!is_doors_open_window(&cfg, pt(today, 6, 0, 0)));
    }
}
