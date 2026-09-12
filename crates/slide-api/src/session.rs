//! The nightly session window — ONE place that decides whether doors are open.
//!
//! Doors are open every day from `SESSION_OPEN_HOUR:SESSION_OPEN_MINUTE` to
//! `SESSION_CLOSE_HOUR:SESSION_CLOSE_MINUTE` in `SESSION_TZ` (default
//! `America/Los_Angeles`, 7:00-8:00 PM). Everything that needs to know "is it
//! date night right now" — `GET /session`, lobby join, the matcher, the doors
//! push — calls [`SessionWindow::compute`] rather than reimplementing the
//! clock math.

use chrono::{DateTime, Duration, NaiveDate, TimeZone, Utc};
use chrono_tz::Tz;
use serde::Serialize;

use crate::config::Config;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionWindow {
    pub is_open: bool,
    pub opens_at: DateTime<Utc>,
    pub closes_at: DateTime<Utc>,
    /// The PT (or `SESSION_TZ`) calendar date this window belongs to.
    pub session_date: NaiveDate,
    pub server_time: DateTime<Utc>,
}

impl SessionWindow {
    /// Compute tonight's window as of `now`. `is_review_account` and
    /// `SESSION_ALWAYS_OPEN` both force the session open (review/dev escape
    /// hatch so App Review and CI aren't at the mercy of the wall clock).
    pub fn compute(cfg: &Config, now: DateTime<Utc>, is_review_account: bool) -> Self {
        if is_review_account || cfg.session_always_open {
            let session_date = now.with_timezone(&cfg.session_tz).date_naive();
            return SessionWindow {
                is_open: true,
                opens_at: now,
                closes_at: now + Duration::hours(1),
                session_date,
                server_time: now,
            };
        }

        let local_now = now.with_timezone(&cfg.session_tz);
        let today = local_now.date_naive();
        let open_today = local_time(
            cfg.session_tz,
            today,
            cfg.session_open_hour,
            cfg.session_open_minute,
        );
        let close_today = local_time(
            cfg.session_tz,
            today,
            cfg.session_close_hour,
            cfg.session_close_minute,
        );

        if local_now < open_today {
            SessionWindow {
                is_open: false,
                opens_at: open_today.with_timezone(&Utc),
                closes_at: close_today.with_timezone(&Utc),
                session_date: today,
                server_time: now,
            }
        } else if local_now < close_today {
            SessionWindow {
                is_open: true,
                opens_at: open_today.with_timezone(&Utc),
                closes_at: close_today.with_timezone(&Utc),
                session_date: today,
                server_time: now,
            }
        } else {
            // Doors closed for tonight; report tomorrow's window.
            let tomorrow = today.succ_opt().unwrap_or(today);
            let open_tomorrow = local_time(
                cfg.session_tz,
                tomorrow,
                cfg.session_open_hour,
                cfg.session_open_minute,
            );
            let close_tomorrow = local_time(
                cfg.session_tz,
                tomorrow,
                cfg.session_close_hour,
                cfg.session_close_minute,
            );
            SessionWindow {
                is_open: false,
                opens_at: open_tomorrow.with_timezone(&Utc),
                closes_at: close_tomorrow.with_timezone(&Utc),
                session_date: tomorrow,
                server_time: now,
            }
        }
    }
}

/// Resolve `date` at `hour:minute` in `tz` to a concrete instant, handling the
/// two DST edge cases. Neither edge case can actually happen at 7 PM / 8 PM
/// (US DST transitions are near 2 AM local), but this stays correct if the
/// window config ever changes.
fn local_time(tz: Tz, date: NaiveDate, hour: u32, minute: u32) -> DateTime<Tz> {
    let naive = date
        .and_hms_opt(hour, minute, 0)
        .unwrap_or_else(|| date.and_hms_opt(0, 0, 0).expect("midnight is always valid"));
    match tz.from_local_datetime(&naive) {
        chrono::LocalResult::Single(dt) => dt,
        // Fall-back (clocks repeat an hour): pick the first (earlier) instant.
        chrono::LocalResult::Ambiguous(earlier, _later) => earlier,
        // Spring-forward (the local time never occurred): nudge forward an
        // hour, which always lands in the resumed, unambiguous range.
        chrono::LocalResult::None => tz
            .from_local_datetime(&(naive + Duration::hours(1)))
            .single()
            .unwrap_or_else(|| Utc.from_utc_datetime(&naive).with_timezone(&tz)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> Config {
        Config {
            session_always_open: false,
            ..Config::from_env()
        }
    }

    /// Build a UTC instant for a given PT wall-clock time on `date`.
    fn pt(date: NaiveDate, hour: u32, minute: u32, second: u32) -> DateTime<Utc> {
        let naive = date.and_hms_opt(hour, minute, second).unwrap();
        chrono_tz::America::Los_Angeles
            .from_local_datetime(&naive)
            .single()
            .expect("unambiguous PT time")
            .with_timezone(&Utc)
    }

    #[test]
    fn closed_one_second_before_open() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        let now = pt(today, 18, 59, 59);
        let w = SessionWindow::compute(&cfg, now, false);
        assert!(!w.is_open);
        assert_eq!(w.session_date, today);
        assert_eq!(w.opens_at, pt(today, 19, 0, 0));
    }

    #[test]
    fn open_at_the_opening_second() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        let now = pt(today, 19, 0, 0);
        let w = SessionWindow::compute(&cfg, now, false);
        assert!(w.is_open);
        assert_eq!(w.session_date, today);
    }

    #[test]
    fn open_one_second_before_close() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        let now = pt(today, 19, 59, 59);
        let w = SessionWindow::compute(&cfg, now, false);
        assert!(w.is_open);
        assert_eq!(w.session_date, today);
    }

    #[test]
    fn closed_at_the_closing_second_and_reports_tomorrow() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        let tomorrow = today.succ_opt().unwrap();
        let now = pt(today, 20, 0, 0);
        let w = SessionWindow::compute(&cfg, now, false);
        assert!(!w.is_open);
        assert_eq!(w.session_date, tomorrow);
        assert_eq!(w.opens_at, pt(tomorrow, 19, 0, 0));
    }

    #[test]
    fn dst_transition_day_still_yields_a_one_hour_window() {
        // 2026-03-08 is when US clocks spring forward (2 AM -> 3 AM), nowhere
        // near the 7-8 PM window, but exercise the date math on that day.
        let cfg = cfg();
        let dst_day = NaiveDate::from_ymd_opt(2026, 3, 8).unwrap();
        let now = pt(dst_day, 19, 30, 0);
        let w = SessionWindow::compute(&cfg, now, false);
        assert!(w.is_open);
        assert_eq!(w.closes_at - w.opens_at, Duration::hours(1));
        assert_eq!(w.session_date, dst_day);
    }

    #[test]
    fn review_account_is_always_open() {
        let cfg = cfg();
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        // High noon: normally closed.
        let now = pt(today, 12, 0, 0);
        let w = SessionWindow::compute(&cfg, now, true);
        assert!(w.is_open);
        assert_eq!(w.session_date, today);
        assert_eq!(w.closes_at - w.opens_at, Duration::hours(1));
    }

    #[test]
    fn session_always_open_overrides_the_clock() {
        let cfg = Config {
            session_always_open: true,
            ..Config::from_env()
        };
        let today = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        let now = pt(today, 3, 0, 0);
        let w = SessionWindow::compute(&cfg, now, false);
        assert!(w.is_open);
    }
}
