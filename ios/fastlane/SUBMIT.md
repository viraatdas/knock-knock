# Slide — finishing the App Store submission

Everything that can be set via the App Store Connect API is **done** (build 4 selected,
categories, age rating 4+, content rights, copyright, auto-release, subtitle, review contact,
screenshots for iPhone 6.9"/6.5" + iPad 12.9", **Free pricing**).

## The one remaining step (Apple makes this web-only)

App Privacy "nutrition label" answers are **not** exposed in the public ASC API, so they must
be set once in the web UI:

1. https://appstoreconnect.apple.com  →  Apps  →  **Slide Video Calls**
2. Left sidebar → **App Privacy** → **Get Started** (or **Edit**)
   - Data collection: **Yes, we collect data from this app**
   - Add **Phone Number** → purpose **App Functionality** → linked to user: **Yes** → tracking: **No**
   - Add **Contacts** → purpose **App Functionality** → linked to user: **Yes** → tracking: **No**
   - **Publish**
3. (Pricing is already Free — no action needed.)

## Then submit (one command)

```bash
cd ios && set -a && . fastlane/.asc.env && set +a
python3 - <<'PY'
import json,os
open('/tmp/asc_proper.json','w').write(json.dumps({
  'key_id': os.environ['ASC_KEY_ID'], 'issuer_id': os.environ['ASC_ISSUER_ID'],
  'key': open(os.environ['ASC_KEY_PATH']).read(), 'in_house': False}))
PY
fastlane deliver --api_key_path /tmp/asc_proper.json --app_identifier app.exla.slide \
  --skip_binary_upload true --skip_screenshots true --skip_metadata true \
  --submit_for_review true --automatic_release true --force true \
  --run_precheck_before_submit false \
  --submission_information '{"add_id_info_uses_idfa": false, "export_compliance_uses_encryption": false}'
```

Verify it actually entered review (don't trust the exit code alone):

```bash
fastlane ios asc_state
# Want: version leaves PREPARE_FOR_SUBMISSION and a reviewSubmission shows WAITING_FOR_REVIEW / IN_REVIEW
```

Then Apple's human review takes ~1–2 days; it auto-releases on approval.
