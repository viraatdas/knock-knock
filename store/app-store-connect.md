# iOS App Store submission

**Bundle ID:** `app.exla.slide` (must match the Xcode project and the App ID
you register). This doesn't change with the pivot.

**Existing app record:** "Knock Knock - Video Chat" (Apple ID 1780017294).
At release time this gets renamed to **Knock Knock - 5 Minute Dates** in App Store
Connect. It's the same app record and the same bundle id, just a new name,
version (1.1.0), and listing.

## Prerequisites (gated, needs a paid Apple Developer Program at $99/yr)
1. Apple Developer Program enrollment (already done for the existing app).
2. In the Developer portal:
   - The App ID's capabilities should now be **Push Notifications** only.
     VoIP is no longer needed: CallKit and PushKit are gone, and there's no
     more incoming-call push. Remove the VoIP capability if it's still
     checked.
   - Keep the APNs Auth Key (`.p8`). It's still used for alert pushes (doors
     open, new match, new message).
3. In App Store Connect:
   - Rename the app record to **Knock Knock - 5 Minute Dates**.
   - Fill the listing from `store/listing.md`.
   - Complete **App Privacy** from `store/privacy.md`.
   - Set the age rating to **17+** (see `submission-checklist.md`).
   - Set categories to **Lifestyle** (primary) / **Social Networking**
     (secondary).
   - Confirm China is removed from the app's Availability. It was in the
     rejection for 1.0.2 alongside CallKit and needs to stay off.
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
`ios/fastlane/metadata/review_information/notes.txt` covers this in full, but
in short:
- Two review phone numbers (`+1 650 555 0100`, `+1 650 555 0101`) with a
  fixed OTP code so the reviewer never hits a real SMS wall.
- Both review accounts always see the doors as open, so a reviewer doesn't
  have to wait for 7 to 8 PM Pacific.
- The first review account has a seeded match with message history, so chat,
  report, block, and unmatch can all be tested on a single device.
- With two devices (or a device and a simulator) signed into both review
  numbers, a reviewer can complete a real five-minute video date end to end.
- State plainly that CallKit and PushKit have been removed from the binary,
  since that's what got 1.0.2 rejected.
- Confirm in-app account deletion exists (guideline 5.1.1(v)): Profile >
  Delete account.

## Common rejection risks (pre-empt them)
- CallKit/VoIP still present anywhere in the binary or entitlements → this is
  what got the last version rejected. Double-check `UIBackgroundModes` is
  `audio` only and there's no `voip` mode left.
- China still listed in Availability → remove it.
- OTP wall with no reviewer path → the two review numbers above.
- Missing account deletion → wire `DELETE /me`, confirm it's reachable from
  Profile.
- Privacy label mismatch → keep `store/privacy.md` accurate as fields change.
- Age rating too low for a dating app with messaging and user-generated
  content → 17+, not 4+.
