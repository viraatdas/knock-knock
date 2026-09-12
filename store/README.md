# Knock Knock: store submission package

Everything needed to submit **Knock Knock - 5 Minute Dates** to the App
Store, kept platform-agnostic here and wired into `ios/fastlane`. Android is
frozen on the old "Knock Knock - Video Chat" calling product and isn't part
of this pivot; its Play listing lives in `android/fastlane/metadata`
untouched.

## What's here
- `listing.md`: shared marketing copy (name, subtitle, description, keywords, categories).
- `privacy.md`: data-safety / privacy-label answers (both stores require these).
- `app-store-connect.md`: iOS submission steps (gated on Apple Developer Program).
- `play-console.md`: Android submission steps (gated on Play Console account).
- `assets.md`: icon + screenshot specs and the shot list.
- `submission-checklist.md`: the end-to-end gate to "live on both stores".

## The honest gating
Both stores require **paid developer accounts** and **human review**, neither of
which can be automated from this machine:
- Apple Developer Program: $99/yr, ~24 to 48h review.
- Google Play Console: $25 one-time, hours to days review (Android only, not
  part of this pivot).

Everything up to "press Submit" is prepared here and in the per-platform
fastlane lanes. Once the account + signing credentials exist, submission is
`cd ios && fastlane release`, or the CI path in `.github/workflows/ios-release.yml`
when local `xcodebuild` can't be used (see `AGENTS.md` "Release Automation").
