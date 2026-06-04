# iOS — App Store submission

**Bundle ID:** `app.exla.slide` (must match the Xcode project & the App ID you
register).

## Prerequisites (gated — needs paid Apple Developer Program, $99/yr)
1. Enroll in the Apple Developer Program.
2. In the Developer portal:
   - Register the App ID with capabilities: **Push Notifications**, **VoIP**
     (for CallKit incoming-call push), **Associated Domains** (optional).
   - Create an **APNs Auth Key** (`.p8`) — used for incoming-call pushes.
3. In App Store Connect:
   - Create the app record (name **Slide**, primary language, bundle id, SKU).
   - Fill the listing from `store/listing.md`.
   - Complete **App Privacy** from `store/privacy.md`.
   - Upload screenshots from `store/assets.md`.

## Signing & upload (fastlane)
`ios/fastlane/Fastfile` provides:
- `fastlane beta` → `build_app` + `upload_to_testflight`.
- `fastlane release` → `build_app` + `upload_to_app_store`.

```bash
cd ios
fastlane match appstore   # provisions distribution certs+profiles (needs a match repo)
fastlane beta             # first TestFlight build
```
App Store Connect API key (for CI, avoids 2FA): App Store Connect → Users and
Access → Integrations → App Store Connect API.

## Review notes to include
- Provide a **reviewer test number / OTP path**: signup is phone-OTP, so Apple
  must be able to get a code or they will reject (guideline 2.1).
- State that calls are 1:1/group video over WebRTC, media not recorded.
- Confirm **in-app account deletion** exists (guideline 5.1.1(v)).

## Common rejection risks (pre-empt them)
- OTP wall with no reviewer path → give a test number/code.
- Missing account deletion → wire `DELETE /me`.
- Privacy label mismatch → keep `store/privacy.md` accurate.
- CallKit without a real call demo → ensure the demo flow completes a call.
