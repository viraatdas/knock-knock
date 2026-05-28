# Slide — store submission package

Everything needed to submit Slide to the **App Store** and **Google Play**,
kept platform-agnostic here and wired into each platform's `fastlane` setup
(`ios/fastlane`, `android/fastlane`).

## What's here
- `listing.md` — shared marketing copy (name, subtitle, description, keywords, categories).
- `privacy.md` — data-safety / privacy-label answers (both stores require these).
- `app-store-connect.md` — iOS submission steps (gated on Apple Developer Program).
- `play-console.md` — Android submission steps (gated on Play Console account).
- `assets.md` — icon + screenshot specs and the shot list.
- `submission-checklist.md` — the end-to-end gate to "live on both stores".

## The honest gating
Both stores require **paid developer accounts** and **human review**, neither of
which can be automated from this machine:
- Apple Developer Program — $99/yr, ~24–48h review.
- Google Play Console — $25 one-time, hours–days review.

Everything up to "press Submit" is prepared here and in the per-platform
fastlane lanes. Once the accounts + signing credentials exist, submission is:
`cd ios && fastlane release` and `cd android && fastlane deploy`.
