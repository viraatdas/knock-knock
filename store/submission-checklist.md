# Submission checklist (the path to live on both stores)

The path from this repo to two live store listings. Items marked 🔒 require a
paid account or human action that cannot be automated from this environment.

Android is frozen at the old "Knock Knock - Video Chat" calling product until
it gets its own pivot, so the Android section below is unchanged from before.
Everything iOS is now for **Knock Knock - 5 Minute Dates** 1.1.0.

## Shared (do once)
- [x] Landing site live (web/ → Vercel) with working `/privacy` + `/terms`.
- [ ] Backend deployed and reachable over HTTPS/WSS. See `AGENTS.md`.
- [ ] Point each client's `Config` base URL at the deployed API (`https://<api>.fly.dev/v1`).
- [ ] SMS provider configured for production (`SMS_PROVIDER=twilio` + creds), or
      Firebase phone auth wired for the iOS client per the current spec.
- [x] Wire **in-app account deletion** → `DELETE /me` (Apple + Play both require it).
- [x] Add a **reviewer test number / OTP bypass** so reviewers can pass the phone wall
      (`REVIEW_PHONES` + `REVIEW_OTP_CODE`, see `ios/fastlane/metadata/review_information/notes.txt`).
- [ ] App icon finalized (`store/assets.md`).
- [x] Android Welcome + Enter-phone screenshots captured; capture the rest per platform.

## iOS 🔒
- [x] 🔒 Apple Developer Program enrollment ($99/yr), already done for the existing app record.
- [ ] App ID capabilities updated: drop VoIP, keep Push Notifications only
      (CallKit and PushKit are removed from the app).
- [ ] App Store Connect record renamed to **Knock Knock - 5 Minute Dates**; listing
      from `store/listing.md`, privacy from `store/privacy.md`.
- [ ] Age rating set to **17+**; categories set to Lifestyle (primary) /
      Social Networking (secondary).
- [ ] China removed from the app's Availability.
- [ ] 🔒 Signing → `cd ios && fastlane beta` (TestFlight).
- [ ] TestFlight smoke: install, sign up, complete a profile, complete a real
      five-minute video date with a second account, get a match, send a
      message.
- [ ] `cd ios && fastlane release` → submit for review.
- [ ] 🔒 Pass App Review (~24–48h). Watch specifically for CallKit/VoIP and
      China availability, since that's what sank 1.0.2 last time.

## Android 🔒 (frozen at the old calling product, not part of this pivot)
- [x] App builds → `assembleDebug` APK at `android/app/build/outputs/apk/debug/`.
- [ ] 🔒 Google Play Console account ($25 one-time).
- [ ] App created; listing + feature graphic + data safety + content rating.
- [ ] 🔒 Upload keystore generated; Play App Signing enrolled.
- [ ] 🔒 Play service account JSON for `supply`.
- [ ] `cd android && fastlane internal` → internal testing.
- [ ] Internal smoke: install, sign up, complete a real call.
- [ ] `cd android && fastlane production` → production.
- [ ] 🔒 Pass Play review.

## Definition of done
The iOS listing shows **"Available"** as Knock Knock - 5 Minute Dates, and the app
installs on a real device, signs up with a phone number, completes a profile,
and gets through a real five-minute video date and a text chat with a match.
Android stays on the old calling product until it's migrated separately.
