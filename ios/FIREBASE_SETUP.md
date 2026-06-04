# Firebase Phone Auth — console setup (one-time, needs your Google login)

The code is done. Firebase sends the SMS via Google's carrier-approved infra, so
there is **no toll-free / 10DLC registration** and it works for real numbers
right away. You just need to create the Firebase project and drop one file in.

## 1. Create the project
1. https://console.firebase.google.com → **Add project** → name it `slide`
   (or reuse an existing Google project). Analytics optional.

## 2. Enable Phone auth
1. Build → **Authentication** → **Get started**
2. **Sign-in method** tab → **Phone** → **Enable** → Save.
3. (Testing convenience) Under Phone → **Phone numbers for testing**, you can add
   a number + a fixed code (e.g. `+1 304 216 4370` → `123456`) so testers don't
   need a real SMS during review. Optional but handy.

## 3. Register the iOS app
1. Project Overview → **Add app** → **iOS**.
2. **Apple bundle ID:** `app.exla.slide`  (must match exactly)
3. App nickname: `Slide iOS`. App Store ID: leave blank for now.
4. **Download `GoogleService-Info.plist`.**

## 4. Give me the plist
Put the downloaded file here:
```
ios/Resources/GoogleService-Info.plist
```
That's it — the app auto-detects it (`Config.useFirebaseAuth`) and switches the
sign-in flow to Firebase. Without the file, the app falls back to the dev-code
flow, so nothing breaks before it's added.

> ⚠️ This file is not a secret in the usual sense (it ships in the app), but keep
> it out of public screenshots. It's fine to commit.

## 5. APNs key (so Firebase can verify the device silently)
Firebase phone auth confirms the device via a silent push before sending the SMS.
Without an APNs key it falls back to a reCAPTCHA web flow (still works, just an
extra tap). To get the clean silent path:
1. Apple Developer → Certificates, IDs & Profiles → **Keys** → **+** → enable
   **Apple Push Notifications service (APNs)** → download the `.p8` + note the
   **Key ID** and your **Team ID** (`3C4383262W`).
2. Firebase console → Project settings → **Cloud Messaging** → **Apple app
   configuration** → upload the APNs **auth key** (.p8 + Key ID + Team ID).

## 6. (For external TestFlight / App Store) URL scheme
Firebase's reCAPTCHA fallback needs the reversed client ID as a URL scheme.
After step 4, open `GoogleService-Info.plist`, copy the `REVERSED_CLIENT_ID`
value, and tell me — I'll add it to the app's URL types in `project.yml`. (If the
APNs key in step 5 is set up, this is rarely hit, but it's good to have.)

---

**What I need back from you:** the `GoogleService-Info.plist` (step 4) at minimum.
Steps 5–6 are polish that make verification smoother but aren't blockers.
