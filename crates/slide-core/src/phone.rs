//! Phone-number normalization to E.164 — the canonical identity for an account.

use crate::error::AppError;

/// Parse and normalize a phone number to E.164 (e.g. `+14155550123`).
///
/// A default region is used only when the input lacks a country code. Callers
/// should prefer fully-qualified `+` numbers from the client.
pub fn normalize_e164(input: &str, default_region: &str) -> Result<String, AppError> {
    let region: phonenumber::country::Id = default_region
        .parse()
        .map_err(|_| AppError::validation("invalid default region"))?;

    let parsed = phonenumber::parse(Some(region), input)
        .map_err(|_| AppError::validation("invalid phone number"))?;

    if !phonenumber::is_valid(&parsed) {
        return Err(AppError::validation("invalid phone number"));
    }

    Ok(parsed.format().mode(phonenumber::Mode::E164).to_string())
}

/// Best-effort normalization for a batch of contact numbers. Numbers that fail
/// to parse are dropped (the client's address book is messy by nature), and the
/// result is de-duplicated while preserving first-seen order.
pub fn normalize_batch(inputs: &[String], default_region: &str) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for raw in inputs {
        if let Ok(e164) = normalize_e164(raw, default_region) {
            if seen.insert(e164.clone()) {
                out.push(e164);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_us_number() {
        assert_eq!(
            normalize_e164("(415) 555-0123", "US").unwrap(),
            "+14155550123"
        );
    }

    #[test]
    fn accepts_already_e164() {
        assert_eq!(
            normalize_e164("+14155550123", "US").unwrap(),
            "+14155550123"
        );
    }

    #[test]
    fn rejects_garbage() {
        assert!(normalize_e164("not-a-phone", "US").is_err());
    }

    #[test]
    fn batch_dedupes() {
        let v = normalize_batch(
            &[
                "+14155550123".into(),
                "(415) 555-0123".into(),
                "garbage".into(),
            ],
            "US",
        );
        assert_eq!(v, vec!["+14155550123".to_string()]);
    }
}
