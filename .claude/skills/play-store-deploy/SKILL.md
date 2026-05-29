---
name: play-store-deploy
description: >-
  Ship the Slide Android app to Google Play (Internal testing or production)
  from the CLI. Generates the upload keystore, wires signing, builds a signed
  AAB, and uploads via fastlane supply. Use when asked to "deploy to play store",
  "ship android", "upload to play console", or "run play-store-deploy".
---

# play-store-deploy

End-to-end Android release for Slide, CLI-driven. Wraps `android/fastlane`.

## What it does
1. **Tooling** — ensures the JDK + Android SDK + fastlane are present.
2. **Keystore** — generates a one-time upload keystore (`keytool`) and writes a
   gitignored `android/keystore.properties` if one doesn't exist.
3. **Build** — `./gradlew bundleRelease` → signed AAB.
4. **Upload** — `fastlane supply` to the requested track.

## Run it
```bash
.claude/skills/play-store-deploy/deploy.sh build_debug   # APK, no account needed
.claude/skills/play-store-deploy/deploy.sh keystore      # generate upload keystore
.claude/skills/play-store-deploy/deploy.sh internal      # signed AAB -> Internal testing
.claude/skills/play-store-deploy/deploy.sh production      # -> production (10% staged)
```

## The manual steps Google requires (one-time)
Unlike iOS, Play has TWO human gates that cannot be scripted:

1. **A Google Play Console developer account** — $25 one-time, tied to your
   Google login. Create at <https://play.google.com/console/signup>. Then create
   the app (name **Slide**, package `app.slide`).
2. **A Play service-account JSON** for `supply`:
   Play Console → Setup → API access → create/link a Google Cloud service
   account → grant it the **Release** permission → download the JSON. Save it to
   `android/fastlane/play-service-account.json` (gitignored) or point
   `PLAY_JSON_KEY` at it.

Everything else — keystore, signing, AAB, upload, staged rollout — the script
does. After the first manual upload, enable **Play App Signing** (Google holds
the app key; you keep the upload key generated here).

## Notes
- `applicationId` is `app.slide` (`android/app/build.gradle.kts`).
- Listing copy: `store/listing.md`; data-safety answers: `store/privacy.md`;
  feature graphic 1024×500 + screenshots: `store/assets.md`.
- Provide a reviewer test phone/OTP path (signup is phone-only) in Play Console →
  App access, or Google will reject.
- Keystore + JSON are gitignored — never commit them. Losing the upload keystore
  after enabling Play App Signing is recoverable (reset upload key in Console);
  losing it before is not — back it up.
