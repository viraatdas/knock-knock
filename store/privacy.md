# Privacy disclosures (App Store Privacy "Nutrition Label" + Play Data Safety)

Both stores require an explicit declaration of what data you collect and why.
Below are the answers that match what Slide's backend actually does (see
`docs/API.md`). Keep these in sync with the code.

## Data collected

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Phone number | Yes | Yes | No | Account identity + authentication |
| Contacts (phone numbers) | Yes | Yes | No | Find which contacts are on Slide (app functionality) |
| Name | Yes (optional) | Yes | No | Display name shown to contacts |
| Photos (avatar) | Yes (optional) | Yes | No | Profile avatar |
| Coarse usage / diagnostics | Yes | No | No | Crash + call-quality metrics |
| Precise location | No | — | — | — |
| Payment info | No | — | — | — |
| Audio/video content | No (not stored) | — | — | Calls are real-time; media is not recorded or stored on servers |

## Key statements (true to the implementation)
- **No email, no password.** Identity is a verified phone number only.
- **Contacts** are normalized to E.164 and matched server-side to find Slide
  users. We do **not** sell address books or expose other people's contacts. (We
  store the owner's own resolved contact rows only.)
- **Call media is not recorded.** Audio/video flows in real time through the SFU
  and is not persisted. (Server-side recording is explicitly a *later, opt-in*
  feature and is OFF.)
- **No third-party advertising SDKs. No tracking across apps/sites.**
- Data deletion: account + associated data deleted on request (wire the
  in-app "delete account" to a `DELETE /me` endpoint before submission — see
  submission-checklist.md; Apple requires in-app account deletion).

## Encryption
- All API + signaling traffic over TLS (HTTPS/WSS).
- Media (WebRTC) is encrypted in transit (DTLS-SRTP) by default.
- Tokens stored in Keychain (iOS) / Keystore-backed EncryptedSharedPreferences (Android).
- Note for store forms: transport is encrypted; calls are **not** end-to-end
  encrypted in v1 because the SFU forwards media (be accurate — do not claim E2EE).
