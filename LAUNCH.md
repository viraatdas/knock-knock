# Slide — launch checklist (two human steps remain)

Everything buildable is built, signed, verified, and committed. The two
remaining steps require credentials only the account owner can create — they
cannot be automated (Apple 2FA / paid Google signup).

## ✅ Done & verified
- Landing site LIVE: https://slide.viraat.dev (white/thin-black, "built for bad internet")
- Listed on https://viraat.dev
- iOS: signed App-Store IPA at /tmp/SlideExport/Slide.ipa
  (Apple Distribution cert, Team 3C4383262W, bundle app.exla.slide,
   get-task-allow=false → valid app-store build; verified with codesign + altool present)
  App Store Connect record: apple_id 1780017294, ITC team 118673131
- Android: signed AAB at android/app/build/outputs/bundle/release/app-release.aab
  (~32.6 MB, upload keystore android/app/slide-upload.keystore — BACK IT UP)
- Both fastlane pipelines + /app-store-deploy and /play-store-deploy skills
- Repo clean, no secrets (pre-commit guard); SECURITY.md documents rotation

## ⏳ Step 1 — iOS to TestFlight + App Store (you: ~2 min)
1. appleid.apple.com → Sign-In and Security → App-Specific Passwords → "+" → name "slide"
2. Give the code to the agent (or run yourself):
   cd ios && export PATH=/opt/homebrew/bin:$PATH
   export FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
   export FASTLANE_ITC_TEAM_ID=118673131
   fastlane pilot upload --ipa /tmp/SlideExport/Slide.ipa \
     --apple_id 1780017294 --app_identifier app.exla.slide \
     --skip_waiting_for_build_processing true
3. Then: fastlane deliver --submit_for_review true --force true
   (metadata + screenshots already in ios/fastlane/metadata/)
   → Apple human review ~24–48h

## ⏳ Step 2 — Android to Play (you: ~10 min)
1. play.google.com/console/signup ($25 one-time) → create app, package app.slide
2. Play Console → Setup → API access → create service account → grant Release →
   download JSON to android/fastlane/play-service-account.json
3. Then: .claude/skills/play-store-deploy/deploy.sh internal
   → uploads app-release.aab to Internal testing → Play review (hours–days)

## Optional — backend live on AWS (you: 1 value)
Put the real Supabase slide-prod DB password in deploy/secrets/aws.env, then
python3 deploy/aws/finalize.py (App Runner deploy + health + smoke).
