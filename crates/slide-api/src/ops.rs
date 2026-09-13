//! One-shot operator commands. `main` runs one of these instead of serving
//! when the first argument names a command; nothing here starts the HTTP
//! server, the matcher, or the doors-open scheduler.
//!
//! `slide-api push-test --phone +14155550137` (or `--user <uuid>`) sends one
//! real APNs alert to every token the account has registered and prints what
//! Apple answered, per token. Meant to run on the Fly machine, where the
//! production secrets are in the environment (see AGENTS.md, "Deployment
//! Status"). It applies the same `APNS_ENV` guard as `serve()`, and its
//! output never carries a full device token or a full phone number: tokens
//! are masked, the phone is echoed as its last four digits only (and not at
//! all for `--user`), and transport errors are formatted without the request
//! URL (`push/apns.rs`, `transport_error`).

use std::time::Duration;

use anyhow::{bail, Context};
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

use slide_core::phone;

use crate::{
    config::Config,
    push::{apns::ApnsError, mask_token, NotifyOutcome, Push},
};

const USAGE: &str = "usage: slide-api push-test (--phone <E.164> | --user <uuid>)";

/// Who the test push goes to.
#[derive(Debug, PartialEq, Eq)]
enum Target {
    Phone(String),
    User(Uuid),
}

/// Accepts `--phone <v>`, `--phone=<v>`, `--user <v>`, `--user=<v>`; exactly
/// one of them. The phone is normalized later, once `Config` is loaded.
fn parse_target(args: &[String]) -> anyhow::Result<Target> {
    let mut target = None;
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        let (flag, value) = match arg.split_once('=') {
            Some((flag, value)) => (flag, value.to_string()),
            None => {
                let value = iter
                    .next()
                    .with_context(|| format!("{arg} needs a value. {USAGE}"))?;
                (arg.as_str(), value.clone())
            }
        };
        let parsed = match flag {
            "--phone" => Target::Phone(value),
            "--user" => Target::User(
                value
                    .parse()
                    .with_context(|| format!("--user must be a uuid, got {value:?}"))?,
            ),
            other => bail!("unknown argument {other:?}. {USAGE}"),
        };
        if target.replace(parsed).is_some() {
            bail!("pass exactly one of --phone or --user. {USAGE}");
        }
    }
    target.with_context(|| format!("missing target. {USAGE}"))
}

#[derive(Debug, sqlx::FromRow)]
struct UserRow {
    id: Uuid,
    phone: String,
    /// Whether the nightly doors-open job would include this account.
    profile_complete: bool,
}

const USER_COLUMNS: &str = "id, phone, profile_completed_at IS NOT NULL AS profile_complete";

/// `***` plus the last four digits (`***4370`): enough to confirm the
/// operator hit the account they meant, not enough to be a phone number in a
/// terminal scrollback or a `fly ssh` transcript.
fn mask_phone(phone: &str) -> String {
    // ASCII digits only, so byte slicing is safe.
    let digits: String = phone.chars().filter(|c| c.is_ascii_digit()).collect();
    let start = digits.len().saturating_sub(4);
    format!("***{}", &digits[start..])
}

/// `slide-api push-test`. Exit status 0 only when APNs accepted at least one
/// token and rejected none; a dead token that got pruned is not a failure
/// (that is the fan-out healing itself), but a config or transport error is.
pub async fn push_test(args: Vec<String>) -> anyhow::Result<()> {
    let target = parse_target(&args)?;
    let cfg = Config::from_env();

    // The same guard `serve()` applies at boot: a wrong APNS_ENV would aim
    // the test push at the wrong Apple host and make Apple's answer
    // meaningless.
    cfg.check_apns_env()?;
    let push = Push::from_config(&cfg);
    if !push.any_enabled() {
        bail!("APNs is not configured: set APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8 and APNS_TOPIC");
    }
    println!("apns env={} topic={}", cfg.apns_env, cfg.apns_topic);

    let db = PgPoolOptions::new()
        .max_connections(2)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&cfg.database_url)
        .await
        .context("connecting to Postgres")?;

    let user: Option<UserRow> = match &target {
        Target::Phone(raw) => {
            let e164 = phone::normalize_e164(raw, &cfg.default_region)
                .with_context(|| format!("invalid phone {raw:?}"))?;
            sqlx::query_as(&format!(
                "SELECT {USER_COLUMNS} FROM users WHERE phone = $1"
            ))
            .bind(&e164)
            .fetch_optional(&db)
            .await
            .context("looking up user by phone")?
        }
        Target::User(id) => {
            sqlx::query_as(&format!("SELECT {USER_COLUMNS} FROM users WHERE id = $1"))
                .bind(id)
                .fetch_optional(&db)
                .await
                .context("looking up user by id")?
        }
    };
    let Some(user) = user else {
        bail!("no user found for {target:?}");
    };
    // The phone is only echoed (last four digits) when the operator typed it
    // in; looked up by id, the output says nothing about the number.
    let phone = match &target {
        Target::Phone(_) => format!(" phone={}", mask_phone(&user.phone)),
        Target::User(_) => String::new(),
    };
    println!(
        "user id={}{phone} doors_open_recipient={}",
        user.id, user.profile_complete
    );

    let mut data = serde_json::Map::new();
    data.insert("type".to_string(), serde_json::json!("doors_open"));
    let deliveries = push
        .deliver_alert(
            &db,
            user.id,
            "Knock Knock",
            "Test: notifications are working.",
            Some("push-test"),
            Some("knock.caf"),
            600,
            Some(&data),
        )
        .await
        .context("loading push subscriptions")?;

    if deliveries.is_empty() {
        bail!(
            "user {} has no apns subscriptions (open the app, allow notifications, then retry)",
            user.id
        );
    }

    let mut outcome = NotifyOutcome::default();
    for delivery in &deliveries {
        let token = mask_token(&delivery.token);
        match &delivery.result {
            Ok(receipt) => {
                outcome.sent += 1;
                println!(
                    "token={token} ok status={} apns-id={}",
                    receipt.status,
                    receipt.apns_id.as_deref().unwrap_or("-")
                );
            }
            Err(ApnsError::DeadToken(msg)) => {
                outcome.pruned += 1;
                println!("token={token} pruned (dead token, row deleted): {msg}");
            }
            Err(ApnsError::Other(msg)) => {
                outcome.failed += 1;
                println!("token={token} failed: {msg}");
            }
        }
    }
    println!(
        "sent={} failed={} pruned={}",
        outcome.sent, outcome.failed, outcome.pruned
    );
    if outcome.sent > 0 {
        println!(
            "note: a 200 from Apple means the push was accepted; the device still has to allow notifications for Knock Knock in Settings."
        );
    }

    if outcome.sent == 0 {
        bail!("push test failed: APNs accepted no token");
    }
    if outcome.failed > 0 {
        bail!("push test failed: {} token(s) rejected", outcome.failed);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{mask_phone, parse_target, Target};

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn mask_phone_keeps_only_the_last_four_digits() {
        assert_eq!(mask_phone("+14155554370"), "***4370");
        assert_eq!(mask_phone("+44 20 7946 0958"), "***0958");
        assert_eq!(mask_phone("123"), "***123");
        assert_eq!(mask_phone(""), "***");
    }

    #[test]
    fn parses_phone_in_both_spellings() {
        assert_eq!(
            parse_target(&args(&["--phone", "+14155550137"])).unwrap(),
            Target::Phone("+14155550137".to_string())
        );
        assert_eq!(
            parse_target(&args(&["--phone=+14155550137"])).unwrap(),
            Target::Phone("+14155550137".to_string())
        );
    }

    #[test]
    fn parses_user_uuid() {
        let id = "0192d0a4-4c7e-7d3a-9f1b-2f3c4d5e6f70";
        assert_eq!(
            parse_target(&args(&["--user", id])).unwrap(),
            Target::User(id.parse().unwrap())
        );
        assert!(parse_target(&args(&["--user", "not-a-uuid"])).is_err());
    }

    #[test]
    fn rejects_missing_extra_or_unknown_arguments() {
        assert!(parse_target(&args(&[])).is_err());
        assert!(parse_target(&args(&["--phone"])).is_err());
        assert!(parse_target(&args(&["--phone", "+14155550137", "--user", "x"])).is_err());
        assert!(parse_target(&args(&["--token", "abc"])).is_err());
    }
}
