# Slide — Android Release Readiness

Status as of **2026-06-03**. App: `app.slide` · versionCode `1` · versionName `1.0.0`.
Play **developer account ID**: `5800243437568042567` (account PAID; Google
verification in progress as of 2026-06-03 — upload is blocked until it clears).

This doc tracks what is already done and the exact remaining human steps to push
the release to Google Play the moment the developer account is verified.

**Console deep links** (work once verified):
- App list: https://play.google.com/console/u/0/developers/5800243437568042567/app-list
- Create app: https://play.google.com/console/u/0/developers/5800243437568042567/create-new-app
- API access (service account): https://play.google.com/console/u/0/developers/5800243437568042567/api-access

---

## DONE (verified)

- [x] **Signed release AAB built** at
      `android/app/build/outputs/bundle/release/app-release.aab`
      (~32 MB, rebuilt against API 35 on 2026-06-03 18:39).
- [x] **AAB validates** — `bundletool validate --bundle <aab>` exits 0 (PASS).
- [x] **Manifest values confirmed** via `bundletool dump manifest`:
  - `package` = `app.slide` ✓
  - `versionCode` = `1` ✓
  - `versionName` = `1.0.0`
  - **`targetSdkVersion` = `35`** ✓ (meets Play's current target-API requirement)
  - `minSdkVersion` = `26` ✓
  - `compileSdkVersion` = `35`
- [x] **AAB is signed** — `jarsigner -verify <aab>` reports **`jar verified`**.
      (A "certificate chain is invalid" warning is expected and harmless for a
      self-signed upload keystore — it is signed, just not chained to a public CA.)
- [x] **Upload keystore backed up** outside git to `~/.slide-android-backup/`
      (dir is `chmod 700`). Copies SHA-256-verified to match the originals:
  - `slide-upload.keystore` → `3d7827fdeadc7cda11d6579bd7f4260f71887a2c9e8e9ce3264d69f83707f39a`
  - `keystore.properties`   → `df99f75499c656f135f8085d266b700f9a15198a2230d023ba3ca68c452f247a`
  - Both `android/slide-upload.keystore` and `android/keystore.properties` are
    **gitignored** (confirmed in `.gitignore` and `android/.gitignore`).
  - ⚠ Losing this keystore **before** Play App Signing is enabled is
    unrecoverable. Keep the backup.
- [x] **Store metadata staged** at `android/fastlane/metadata/android/en-US/`:
      `title.txt` (5/30), `short_description.txt` (71/80),
      `full_description.txt` (559/4000), `changelogs/1.txt`.
- [x] **Store graphics staged** (generated reproducibly via
      `android/tools/play_assets.py`):
  - `images/featureGraphic/feature.png` — 1024×500, RGB (no alpha) ✓
  - `images/icon/icon.png` — 512×512, RGBA (32-bit) ✓
  - `images/phoneScreenshots/01..05.png` — five 1080×1920 RGB shots
    (welcome, enter-phone, recents, contact sheet, in-call).
  - These are on-brand mockups, not live device captures — fine to launch with;
    swap for real captures later if desired.
  - To push the listing **text + images together** with the AAB, use the new
    `internal_full` fastlane lane (plain `internal` skips metadata/images).
- [x] **bundletool installed** (v1.18.3 via Homebrew).
- [x] **Fastlane Appfile sanity-checked**: `package_name("app.slide")` and
      `json_key_file("fastlane/play-service-account.json")` are correct.

---

## REMAINING — human steps (require the verified Play account)

These cannot be automated from this environment; they need the paid, verified
Google Play Console account ($25 one-time).

### (a) Create the app in Play Console
- Go to https://play.google.com/console → **Create app**.
- App name: **Slide** · package / application ID: **`app.slide`**.
- Complete the one-time listing gates Play requires before a release can go
  live: store listing (uses staged metadata above), Data safety form, Content
  rating questionnaire, target audience, and feature graphic + screenshots.
  (Internal-testing upload itself does not need all of these, but production
  promotion does.)

### (b) Create + download the Play service-account JSON
- Play Console → **Setup → API access → Service accounts** → create a service
  account, **grant it the "Release" permission** for the app.
- Download the JSON key and save it to **exactly**:
  `android/fastlane/play-service-account.json` (gitignored; absent on purpose).
- The Appfile already points `json_key_file` at `fastlane/play-service-account.json`.

### (c) Upload — single command
From the repo root, run:

```
cd android && fastlane internal_full      # AAB + listing text + screenshots + graphics
```

or, to upload **just the AAB** (no listing/images):

```
.claude/skills/play-store-deploy/deploy.sh internal
```

Either does a clean `gradle bundle` (signs the AAB with the upload keystore) and
uploads to the **Internal testing** track as a **draft**. `internal_full` also
pushes the staged metadata + graphics. After it finishes, add testers in Play
Console and promote.

To later go to production (10% staged rollout):

```
.claude/skills/play-store-deploy/deploy.sh production
```

---

## Reviewer / App-access requirements (from store/submission-checklist.md)

Both of these are cross-store requirements that Play **will** check — wire them
before submitting for review, not after:

- **Phone-OTP wall → reviewer test number / OTP bypass.** Slide gates sign-up
  behind a phone-number OTP. Play reviewers cannot receive your SMS, so provide
  a **reviewer test number with a fixed/bypass OTP** and document it in Play
  Console under **App content → App access** (provide demo credentials). Without
  this, review fails at the login wall.
- **In-app account deletion.** Play requires an in-app path to delete the
  account (wired to `DELETE /me`) **and** a publicly reachable account-deletion
  URL declared in the Data safety form. Ensure this is shipped and declared.

Also still open from the shared checklist (not Android-specific but blocks a
working review): backend deployed over HTTPS/WSS, each client `Config` base URL
pointed at the deployed API, and production SMS provider configured.
