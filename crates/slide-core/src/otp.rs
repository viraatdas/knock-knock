//! One-time-passcode generation and constant-time verification.
//!
//! Codes are 6 random digits. We never store the plaintext code — only a
//! peppered SHA-256 hash. The OTP record lives in Redis with a TTL and an
//! attempt counter, so low-entropy codes are protected by short expiry +
//! rate limiting rather than by a slow hash.

use rand::Rng;
use sha2::{Digest, Sha256};

/// Generate a random 6-digit numeric code, zero-padded.
pub fn generate_code() -> String {
    let n: u32 = rand::thread_rng().gen_range(0..1_000_000);
    format!("{n:06}")
}

/// Hash `code` with a server-side pepper and the target phone, hex-encoded.
/// Binding the phone in prevents a hash captured for one number being replayed
/// against another.
pub fn hash_code(code: &str, phone: &str, pepper: &str) -> String {
    let mut h = Sha256::new();
    h.update(pepper.as_bytes());
    h.update(b"|");
    h.update(phone.as_bytes());
    h.update(b"|");
    h.update(code.as_bytes());
    hex::encode(h.finalize())
}

/// Constant-time comparison of a submitted code against a stored hash.
pub fn verify_code(code: &str, phone: &str, pepper: &str, stored_hash: &str) -> bool {
    let computed = hash_code(code, phone, pepper);
    constant_time_eq::constant_time_eq(computed.as_bytes(), stored_hash.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_code_is_six_digits() {
        for _ in 0..100 {
            let c = generate_code();
            assert_eq!(c.len(), 6);
            assert!(c.chars().all(|ch| ch.is_ascii_digit()));
        }
    }

    #[test]
    fn verify_matches() {
        let h = hash_code("123456", "+14155550123", "pepper");
        assert!(verify_code("123456", "+14155550123", "pepper", &h));
        assert!(!verify_code("654321", "+14155550123", "pepper", &h));
        // same code, different phone -> different hash
        assert!(!verify_code("123456", "+14155550999", "pepper", &h));
    }
}
