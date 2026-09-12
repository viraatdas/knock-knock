# Security & secrets policy

Knock Knock handles phone numbers, location, chat messages, auth tokens, and
signing/deploy credentials. This document records how secrets are kept **out
of the repo** and what to rotate if something leaks.

## Golden rule
**No secret ever gets committed.** All credentials live in gitignored files,
the environment, or GitHub Actions secrets, never in tracked source.
Verified: `git ls-files` shows zero secret files, and the full history
contains no AWS key / Apple session / private key (audited 2026-05-28).

## Where each secret lives (all gitignored)
| Secret | Location | Notes |
|---|---|---|
| Backend env (DB, Redis, JWT, OTP pepper, APNs, LiveKit, review accounts) | `.env` (local), Fly secrets (prod) | template: `.env.example` (placeholders only) |
| Firebase iOS client config | `ios/Resources/GoogleService-Info.plist` | gitignored; also stored as the CI secret below |
| AWS deploy secrets | `deploy/secrets/aws.env` | `secrets/` is gitignored |
| Apple session / ASC API key (local fastlane) | `ios/fastlane/.asc.env` | `FASTLANE_SESSION` or API `.p8` |
| Android upload keystore | `android/slide-upload.keystore` + `android/keystore.properties` | `*.keystore`, `*.jks`, `keystore.properties` ignored; frozen product, kept for the existing calling app |
| App Review notes (review-account OTP) | `ios/fastlane/metadata/review_information/notes.txt` | ignored; template `notes.example.txt`; value also lives in Fly secret `REVIEW_OTP_CODE` |
| Play service account | `android/fastlane/play-service-account.json` | `**/*service-account*.json` ignored |

`.env.example` and `keystore.properties.example` are the only credential-shaped
files in git, and contain placeholders only.

## GitHub Actions secrets (`.github/workflows/ios-release.yml`)
The CI archive/upload path for iOS (used when Xcode's build service deadlocks
locally, see `AGENTS.md` "Release Automation") reads these repo secrets. None
of them are ever written to the repo; the workflow decodes them into the
runner's temp directory and cleans up its keychain when it finishes.

| Secret | Contents |
|---|---|
| `IOS_DIST_P12_B64` | Apple Distribution signing identity, base64-encoded `.p12` |
| `IOS_DIST_P12_PASSWORD` | Password for that `.p12` |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | App Store Connect API issuer id |
| `ASC_KEY_P8_B64` | App Store Connect API private key, base64-encoded `.p8` |
| `APPLE_TEAM_ID` | 10-char Apple team id |
| `GOOGLE_SERVICE_INFO_PLIST_B64` | Firebase `GoogleService-Info.plist`, base64-encoded |

Rotate any of these the same way as their local-file equivalents below (new
`.p8`/`.p12`, or a fresh Firebase config download), then update the GitHub
secret and delete the old value from wherever it was generated.

## Defenses in place
1. **`.gitignore`** covers every secret path above.
2. **Pre-commit hook** (`.githooks/pre-commit`, enabled via
   `git config core.hooksPath .githooks`) blocks a commit if it detects an AWS
   access key, a PEM/`.p8` private key, an Apple `myacinfo` session cookie, or a
   staged secret-shaped filename. Run `scripts/install-hooks.sh` once per clone.
3. CI builds use repository **secrets** (e.g. `FLY_API_TOKEN`, the iOS release
   secrets above), never inline.

## Sound assets
Every `.caf` under `ios/Resources/` is synthesized by
`ios/tools/make_sounds.py`, not licensed audio, so there's no rights issue to
manage here anymore. Regenerate them with that script rather than dropping in
a found sound file.

## If a credential leaks — rotate immediately
- **AWS key** (`project-leo`): IAM → Users → Security credentials → delete +
  create new → `aws configure --profile slide`.
- **Apple session**: expires on its own; re-run `fastlane spaceauth`. For a
  durable credential use an App Store Connect API key and revoke it if exposed.
- **App Store Connect API key** (local or the CI `ASC_*` secrets): revoke at
  App Store Connect → Users and Access → Integrations, generate a new key,
  update `ios/fastlane/.asc.env` and the GitHub secrets.
- **Apple Distribution `.p12`** (`IOS_DIST_P12_B64`/`IOS_DIST_P12_PASSWORD`):
  revoke the certificate at developer.apple.com, export a new one, re-encode
  and replace both GitHub secrets.
- **Firebase config** (`GOOGLE_SERVICE_INFO_PLIST_B64`): this file is a client
  identifier, not a bearer secret, but if the project itself is compromised
  rotate it in the Firebase console and update the local file and the secret.
- **Play service account**: Google Cloud IAM → disable/rotate the key.
- **JWT/OTP pepper/APNs key**: regenerate (`openssl rand -hex 32` for the
  first two) and redeploy as a Fly secret.

> Note: an AWS key was pasted into a chat during development. Treat it as
> compromised and rotate it regardless of current validity.
