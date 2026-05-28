//! slide-core — shared types and crypto for the Slide backend.
//!
//! Houses the data models, error type, JWT/token logic, phone normalization,
//! OTP hashing, and TURN credential minting used by both `slide-api`
//! (control plane) and `slide-sfu` (media).

pub mod error;
pub mod jwt;
pub mod models;
pub mod otp;
pub mod phone;
pub mod turn;

pub use error::{AppError, AppResult};
