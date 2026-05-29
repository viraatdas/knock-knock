# Security & secrets policy

Slide handles phone numbers, auth tokens, and signing/deploy credentials. This
document records how secrets are kept **out of the repo** and what to rotate if
something leaks.

## Golden rule
**No secret ever gets committed.** All credentials live in gitignored files or
the environment, never in tracked source. Verified: `git ls-files` shows zero
secret files, and the full history contains no AWS key / Apple session / private
key (audited 2026-05-28).

## Where each secret lives (all gitignored)
| Secret | Location | Notes |
|---|---|---|
| Backend env (DB, Redis, JWT, OTP pepper, TURN) | `.env` (local), platform env (prod) | template: `.env.example` (placeholders only) |
| AWS deploy secrets | `deploy/secrets/aws.env` | `secrets/` is gitignored |
| Apple session / ASC API key | `ios/fastlane/.asc.env` | `FASTLANE_SESSION` or API `.p8` |
| Android upload keystore | `android/slide-upload.keystore` + `android/keystore.properties` | `*.keystore`, `*.jks`, `keystore.properties` ignored |
| Play service account | `android/fastlane/play-service-account.json` | `**/*service-account*.json` ignored |

`.env.example` and `keystore.properties.example` are the only credential-shaped
files in git, and contain placeholders only.

## Defenses in place
1. **`.gitignore`** covers every secret path + ringtone audio (see below).
2. **Pre-commit hook** (`.githooks/pre-commit`, enabled via
   `git config core.hooksPath .githooks`) blocks a commit if it detects an AWS
   access key, a PEM/`.p8` private key, an Apple `myacinfo` session cookie, or a
   staged secret-shaped filename. Run `scripts/install-hooks.sh` once per clone.
3. CI builds use repository **secrets** (e.g. `FLY_API_TOKEN`), never inline.

## Ringtone audio (licensing)
Do **not** commit `ringtone.caf` / `ringtone.mp3` etc. — bundling copyrighted
audio is an App Store / Play rejection and a rights violation. The mechanism is
wired (see `ios/Resources/RINGTONE.md`); drop a **licensed/royalty-free** file
locally and it's picked up at build, but the audio stays out of git.

## If a credential leaks — rotate immediately
- **AWS key** (`project-leo`): IAM → Users → Security credentials → delete +
  create new → `aws configure --profile slide`.
- **Apple session**: expires on its own; re-run `fastlane spaceauth`. For a
  durable credential use an App Store Connect API key and revoke it if exposed.
- **Play service account**: Google Cloud IAM → disable/rotate the key.
- **JWT/OTP/TURN secrets**: regenerate (`openssl rand -hex 32`) and redeploy.

> Note: an AWS key was pasted into a chat during development. Treat it as
> compromised and rotate it regardless of current validity.
