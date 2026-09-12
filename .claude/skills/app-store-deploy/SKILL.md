---
name: app-store-deploy
description: >-
  Ship the Slide iOS app to TestFlight / the App Store entirely from the CLI.
  Installs tooling (xcodegen, fastlane) if missing, generates the Xcode project,
  archives a signed build, and uploads + submits for review using an App Store
  Connect API key. Use when asked to "deploy to the app store", "ship iOS",
  "push to TestFlight", "submit Slide for review", or "run app-store-deploy".
---

# app-store-deploy

End-to-end iOS release for Slide, CLI-driven and re-runnable. Wraps
`ios/fastlane` so a single command takes the app from source → App Store.

## What it does (in order)
1. **Tooling** — ensures `xcodegen` and `fastlane` are installed (`brew install`
   if missing).
2. **Auth** — finds an App Store Connect API key (env vars or
   `ios/fastlane/.asc.env`, which is gitignored). The key gives 2FA-free,
   fully-scriptable access to upload + submit.
3. **Project** — `xcodegen generate` for a reproducible `Slide.xcodeproj`.
4. **Ship** — runs the requested fastlane lane:
   - `build_sim` — unsigned Simulator build (no account needed; sanity check).
   - `bootstrap` — create the App Store Connect app record (idempotent).
   - `beta` — archive + upload to TestFlight.
   - `release` — archive + upload + **submit for review**.
   - `tf_beta_meta`, `tf_beta_submit`, `tf_public_link`, `tf_invite` — external
     TestFlight tester setup after a build is uploaded.

## The one manual step Apple requires (≈60 s, once)
Apple does **not** allow creating the *first* App Store Connect API key over the
API (chicken-and-egg). Create it once in the web UI; everything else is
automated forever after.

1. Open **https://appstoreconnect.apple.com/access/integrations/api**
   (Users and Access → Integrations → App Store Connect API → Team Keys).
2. **Generate API Key**, role **App Manager** (or Admin). Name it `slide-ci`.
3. Note the **Key ID** and the **Issuer ID** (shown at the top of the page).
4. **Download** the `.p8` (one-time download) — save it, do NOT commit it.
5. Tell the skill where it is, either by env or the config file:

   ```bash
   # Option A — config file (gitignored):
   cat > ios/fastlane/.asc.env <<EOF
   ASC_KEY_ID=XXXXXXXXXX
   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ASC_KEY_PATH=$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
   APPLE_TEAM_ID=XXXXXXXXXX        # 10-char Team ID from developer.apple.com → Membership
   APP_IDENTIFIER=app.exla.slide
   EOF
   ```

   The Team ID is at **https://developer.apple.com/account** → Membership details.

## Run it

```bash
.claude/skills/app-store-deploy/deploy.sh build_sim     # no account needed
.claude/skills/app-store-deploy/deploy.sh bootstrap     # create the app record
.claude/skills/app-store-deploy/deploy.sh beta          # → TestFlight
.claude/skills/app-store-deploy/deploy.sh release        # → App Store, submit for review
.claude/skills/app-store-deploy/deploy.sh tf_beta_meta   # external beta metadata
.claude/skills/app-store-deploy/deploy.sh tf_beta_submit # submit Beta App Review
.claude/skills/app-store-deploy/deploy.sh tf_public_link # public external group link
```

The script auto-loads `ios/fastlane/.asc.env`, checks that the key material is
present, and fails with exact missing-piece instructions if anything is absent.
Fastlane performs the App Store Connect token check when the lane runs.

## Notes
- Bundle id is `app.exla.slide` (see `ios/project.yml`). Match the App ID you register.
- Signing uses Automatic with `APPLE_TEAM_ID`; for CI/multiple machines switch to
  `fastlane match` (documented in `ios/README.md`).
- Screenshots in `ios/screenshots/` + listing copy in `store/listing.md` feed
  `upload_to_app_store`; privacy answers are in `store/privacy.md`.
- Review is human (~1–2 days) and out of CLI scope — the skill submits; Apple
  decides.

## Local build hang on this Mac (Xcode 26.6)
`xcodebuild archive` / `fastlane gym` never return here: Xcode 26.6's
`SWBBuildService` deadlocks running a `clang -v -E -dM` capability probe into
an undrained 16 KB pipe. Pass a wrapper compiler that answers the probe
directly and execs straight through to the real `clang` for everything else:

```bash
CC=ios/tools/clang-probe-wrapper.sh CPLUSPLUS=ios/tools/clang-probe-wrapper++.sh \
  .claude/skills/app-store-deploy/deploy.sh beta
```

Any `xcodebuild`/`fastlane gym` invocation on this machine needs both env
vars set; they're transparent on machines that don't have the deadlock, so
it's safe to always pass them here. See `AGENTS.md` "Release Automation" for
the full explanation.

## CI alternative: `.github/workflows/ios-release.yml`
When you'd rather not fight the local build service at all, archive on a
clean macOS GitHub Actions runner instead:

```bash
gh workflow run ios-release.yml -f build_number=33
```

It restores the signing identity, the App Store Connect API key, and the
Firebase config from repo secrets (`IOS_DIST_P12_B64`, `IOS_DIST_P12_PASSWORD`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_B64`, `APPLE_TEAM_ID`,
`GOOGLE_SERVICE_INFO_PLIST_B64` — see `SECURITY.md`), archives, checks that no
CallKit/PushKit symbols linked into the binary, and uploads the `.ipa` to App
Store Connect. Submission for review still happens afterward from a
maintainer's machine with `fastlane ios submit_review` (ASC API only, no
build), once the uploaded build finishes processing.
