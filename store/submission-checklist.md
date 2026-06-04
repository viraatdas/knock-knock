# Submission checklist — "live on both stores"

The path from this repo to two live store listings. Items marked 🔒 require a
paid account or human action that cannot be automated from this environment.

## Shared (do once)
- [x] Landing site live (web/ → Vercel) with working `/privacy` + `/terms`.
- [ ] Backend deployed and reachable over HTTPS/WSS. See `AGENTS.md`.
- [ ] Point each client's `Config` base URL at the deployed API (`https://<api>.fly.dev/v1`).
- [ ] SMS provider configured for production (`SMS_PROVIDER=twilio` + creds).
- [ ] Wire **in-app account deletion** → `DELETE /me` (Apple + Play both require it).
- [ ] Add a **reviewer test number / OTP bypass** so reviewers can pass the phone wall.
- [ ] App icon finalized (`store/assets.md`).
- [x] Android Welcome + Enter-phone screenshots captured; capture the rest per platform.

## iOS 🔒
- [ ] 🔒 Apple Developer Program enrollment ($99/yr).
- [ ] 🔒 App ID + Push/VoIP capabilities + APNs `.p8` key.
- [ ] App Store Connect record + listing + privacy.
- [ ] 🔒 Signing → `cd ios && fastlane beta` (TestFlight).
- [ ] TestFlight smoke: install, sign up, complete a real call.
- [ ] `cd ios && fastlane release` → submit for review.
- [ ] 🔒 Pass App Review (~24–48h).

## Android 🔒
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
Both listings show **"Available"** and the app installs from the public store on
a real device, signs up with a phone number, and completes a video call through
the deployed SFU.
