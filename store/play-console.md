# Android — Google Play submission

**Application ID:** `app.slide` (matches `android/app/build.gradle.kts`).

## Prerequisites (gated — needs Google Play Console account, $25 one-time)
1. Create a Play Console developer account.
2. Create the app (name **Slide**, default language, app/game = app, free).
3. Store listing from `store/listing.md` + assets from `store/assets.md`
   (Play also needs a **feature graphic** 1024×500).
4. Required declarations:
   - **Data safety** form from `store/privacy.md`.
   - **Content rating** questionnaire (real-time user comms → likely Teen).
   - **App access**: reviewer instructions + a test phone number/OTP path.
   - **Target audience**, **Ads** (Slide has no ads) declarations.

## Signing
Use **Play App Signing** (Google holds the app signing key; you hold an upload key):
```bash
cd android
keytool -genkey -v -keystore slide-upload.keystore -alias slide \
  -keyalg RSA -keysize 2048 -validity 10000
# Point signingConfigs at a gitignored keystore.properties
# (storeFile/storePassword/keyAlias/keyPassword). See keystore.properties.example.
```
Keep the keystore + `keystore.properties` OUT of git (already gitignored).

## Build & upload (fastlane)
`android/fastlane/Fastfile` provides:
- `fastlane internal` → `gradle bundleRelease` + `supply` to **internal testing**.
- `fastlane deploy` → `bundleRelease` + `supply` to **production** (staged rollout).

`supply` needs a **Play service account JSON** (Play Console → Setup → API access).
Point fastlane at it via `json_key` in `android/fastlane/Appfile`.

```bash
cd android
fastlane internal   # first AAB to internal testing
fastlane deploy     # production, staged rollout
```

## Common rejection risks (pre-empt them)
- OTP wall → give reviewers a test number/code in **App access**.
- Data safety mismatch → keep `store/privacy.md` accurate (esp. contacts).
- Mic/camera + foreground-service justification for calls → declare in listing.
- Account deletion path required → wire `DELETE /me` + a web deletion link.
