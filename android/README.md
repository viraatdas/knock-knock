# Slide — Android

A phone-only video calling app. Kotlin + Jetpack Compose + Material3, MVVM with
ViewModels + StateFlow, built against the contracts in
[`docs/API.md`](../docs/API.md) and [`docs/DESIGN.md`](../docs/DESIGN.md).

- `minSdk` 26, `targetSdk` / `compileSdk` 34
- Application id `ai.exla.slide` (debug builds use `ai.exla.slide.debug`)
- Gradle (Kotlin DSL) with the version catalog in `gradle/libs.versions.toml`

The build is verified: `./gradlew assembleDebug` produces
`app/build/outputs/apk/debug/app-debug.apk`. Real screenshots of the Welcome
and Enter-phone screens (captured from the running app on an android-34 arm64
emulator) live in `screenshots/`.

---

## 1. Toolchain setup (macOS / Homebrew)

This project was bootstrapped on a clean Mac with no JDK and no Android SDK.
The exact, reproducible steps:

### JDK 17

The `temurin@17` **cask** requires `sudo` (no TTY in automated/sandbox shells),
so use the keg-only **formula** instead — no `sudo` needed:

```bash
brew install openjdk@17
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
"$JAVA_HOME/bin/java" -version   # OpenJDK 17.0.19
```

(If you prefer the cask and have an interactive terminal:
`brew install --cask temurin@17`, then `JAVA_HOME=$(/usr/libexec/java_home -v 17)`.)

### Android SDK (command-line tools)

```bash
brew install --cask android-commandlinetools
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" \
  "platform-tools" "platforms;android-34" "build-tools;34.0.0" \
  "emulator" "system-images;android-34;google_apis;arm64-v8a"
```

### Installed versions (this machine)

| Component | Version |
|---|---|
| JDK | OpenJDK 17.0.19 (Homebrew `openjdk@17`) |
| Android cmdline-tools | cask `android-commandlinetools` (build 14742923) |
| platform-tools (adb) | 1.0.41 |
| Android platform | android-34 |
| build-tools | 34.0.0 |
| emulator | r35.x (arm64) |
| system image | `system-images;android-34;google_apis;arm64-v8a` |
| Gradle | 8.9 (via wrapper) |
| Android Gradle Plugin | 8.5.2 |
| Kotlin | 2.0.20 |

### `local.properties`

`local.properties` (gitignored) points Gradle at the SDK:

```properties
sdk.dir=/opt/homebrew/share/android-commandlinetools
```

---

## 2. Build & run

Always export `JAVA_HOME` (the system `java` may be missing or wrong):

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

cd android
./gradlew assembleDebug          # → app/build/outputs/apk/debug/app-debug.apk
```

### Run on an emulator

```bash
avdmanager create avd -n slide_test \
  -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_6 --force

emulator -avd slide_test -no-snapshot -gpu swiftshader_indirect &
adb wait-for-device
adb install -r -g app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n ai.exla.slide.debug/ai.exla.slide.MainActivity
```

### Backend base URL

`API_BASE_URL` / `WS_BASE_URL` are `buildConfigField`s in `app/build.gradle.kts`.
Defaults target the emulator → host bridge:

- REST: `http://10.0.2.2:8080/v1`
- WS:   `ws://10.0.2.2:8080/v1/ws`

`10.0.2.2` is the emulator's alias for the host machine's `localhost`. Change
these fields (or add product flavors) for staging/production. Cleartext is
enabled (`usesCleartextTraffic`) for local dev only — disable for release.

---

## 3. Architecture

MVVM. Compose UI ← ViewModel (StateFlow) ← Repository ← Retrofit/OkHttp.
Manual DI via a small `AppContainer` constructed in `SlideApp` (Application).

```
ai.exla.slide
├── SlideApp                Application; builds AppContainer, registers Telecom account
├── AppContainer            Manual DI graph (lazy singletons)
├── MainActivity            Edge-to-edge Compose host + splash
├── data
│   ├── model/Models.kt     kotlinx-serialization data classes (camelCase, per API.md)
│   ├── api
│   │   ├── SlideApi.kt     Retrofit interface — every endpoint in API.md
│   │   └── ApiClient.kt    OkHttp + Retrofit + kotlinx-serialization, base URL configurable
│   ├── auth
│   │   ├── TokenStore.kt          EncryptedSharedPreferences (Keystore-backed)
│   │   ├── AuthInterceptor.kt     Adds Bearer token (skips auth endpoints)
│   │   └── TokenAuthenticator.kt  Silent refresh on 401 → POST /auth/refresh
│   └── repo/SlideRepository.kt    Coroutine wrapper, persists auth side-effects
├── signaling/SignalingClient.kt   OkHttp WebSocket /v1/ws?token=, heartbeat + backoff
├── call
│   ├── CallService.kt      Interface over the media engine
│   ├── MockCallService.kt  DEFAULT — renders in-call UI without a device/SFU
│   ├── WebRtcCallService.kt Real org.webrtc PeerConnection → sfuUrl + iceServers
│   └── telecom/            Self-managed ConnectionService so calls ring natively
├── ui
│   ├── theme/              Color, Type, Shape, Theme — all DESIGN.md tokens
│   ├── components/         PrimaryButton, SecondaryButton, Hairline, AvatarCircle,
│   │                       CircleIconButton, EmptyState, quietClickable
│   ├── onboarding/         AuthViewModel + Welcome/Phone/Code/Name screens
│   ├── calls/              CallsViewModel + CallsScreen (Recents home)
│   ├── contacts/           ContactsViewModel + ContactsScreen (search, sections, sheet)
│   ├── incall/             InCallViewModel + InCallScreen + IncomingCallScreen
│   ├── profile/            ProfileViewModel + ProfileScreen
│   ├── nav/                RootNav (Auth/Main/InCall) + MainShell (3-tab bottom nav)
│   └── VmFactory.kt        Single ViewModelProvider.Factory from AppContainer
└── util/Formatters.kt      Duration + quiet relative-time formatting
```

### Screens (all per DESIGN.md — pure white, thin near-black type, hairlines)

1. **Onboarding** — phone-only. Welcome → Phone (`POST /auth/request-otp`) →
   6-digit OTP with auto-advance/auto-submit + resend countdown
   (`POST /auth/verify-otp`, tokens stored encrypted, `POST /devices`) → Name for
   new users (`PATCH /me`).
2. **Calls (Recents)** — wordmark + new-call icon, list with initials circle,
   name, "Incoming · 12m" / "Missed" (subtle red), call-back icon; empty state
   "No calls yet". `GET /calls`.
3. **Contacts** — pinned search, alphabetical sections, "Invite" for non-Slide
   rows, tap → bottom sheet with large name + two thin-outlined circular call
   actions. `POST /contacts/sync`, `GET /contacts`.
4. **In-call** — full-screen, chrome auto-fades after ~4s (tap to reveal),
   draggable rounded self-view, bottom row of thin circular buttons (mute,
   camera flip, video, red end-call), top name + timer; audio-only → centered
   avatar on white. **Incoming call**: full white, large avatar + name with a
   gentle pulse (1.0→1.04), black Accept / red Decline.
5. **Profile** — large avatar, name (tap to edit → `PATCH /me`), phone, settings
   list with hairline dividers, log out in subtle red (`POST /auth/logout`).

### WebRTC + Telecom

- `WebRtcCallService` builds a `PeerConnectionFactory`, captures camera+mic,
  configures the `iceServers` from `/calls`, connects to `sfuUrl` with the
  room-scoped `joinToken`, and runs SDP offer/answer + ICE trickle. The media
  pipeline (capture, encode, tracks, ICE) is fully wired; the exact on-wire SFU
  envelope field names follow `docs/SFU.md` and may need alignment once the SFU
  is reachable.
- **The app defaults to `MockCallService`** (see `AppContainer.callService`) so
  every screen renders without a device camera or a live SFU. Swap to
  `WebRtcCallService(appContext)` for real media on a device. This is why media
  could not be end-to-end verified in this headless environment.
- `telecom/SlideConnectionService` is a self-managed `ConnectionService`
  registered at startup so Slide calls ring through the OS Telecom framework;
  `TelecomBridge` forwards system answer/reject/disconnect to the app layer.

---

## 4. Verification status

- `./gradlew assembleDebug` → **BUILD SUCCESSFUL**, APK at
  `app/build/outputs/apk/debug/app-debug.apk` (~60 MB; bundles WebRTC native
  libs for arm64-v8a/armeabi-v7a/x86/x86_64).
- Emulator (android-34 arm64) boots; APK installs and launches.
- `screenshots/01-welcome.png` and `screenshots/02-enter-phone.png` are real
  captures from the running app.
- Media wiring (WebRTC ↔ live SFU) is **not** end-to-end verified — no physical
  device + reachable SFU in this environment. The mock service stands in so the
  UI is fully exercisable.

---

## 5. Gated release — requires a paid Google Play Developer account

These steps need a Play Console account ($25 one-time) and cannot be completed
here. Everything is scaffolded and submission-ready.

### a. Generate an upload keystore (one time)

```bash
keytool -genkey -v -keystore slide-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias slide
```

### b. Configure signing (gitignored)

Copy `keystore.properties.example` → `keystore.properties` and fill in the
keystore path + passwords. `app/build.gradle.kts` auto-loads it and wires the
`release` signing config when present.

```properties
storeFile=/absolute/path/to/slide-release.jks
storePassword=…
keyAlias=slide
keyPassword=…
```

### c. Build the release App Bundle (AAB)

```bash
./gradlew bundleRelease   # → app/build/outputs/bundle/release/app-release.aab
```

### d. Play Console (manual, account required)

1. Create the app `ai.exla.slide` in the Play Console.
2. Complete the content rating, data-safety form, privacy policy URL, and
   store listing (Slide does video calls — declare camera/mic usage).
3. **Play App Signing**: upload the AAB; let Google manage the app signing key.
4. Upload to the **Internal testing** track first, then promote.

### e. Automated upload via fastlane `supply` (scaffolded)

`fastlane/Appfile` + `fastlane/Fastfile` are ready:

```bash
gem install fastlane

# Internal testing (draft):
fastlane internal
# Promote to production with a 10% staged rollout:
fastlane production
```

Requirements before these lanes work:
- A Play Console **service-account JSON** key (Play Console → Setup → API access).
  Save it as `fastlane/play-service-account.json` (gitignored) — referenced by
  `Appfile`.
- The release keystore + `keystore.properties` from step (b).
- The app must already exist in the Play Console with at least one manual
  upload to create the listing (Google's first-upload requirement).

### Remaining checklist for a real submission

- [ ] Replace the FCM push token placeholder in `AuthViewModel.verifyOtp` with a
      real Firebase Cloud Messaging token (`POST /devices`).
- [ ] Provide adaptive launcher icons at full density (the included vector
      adaptive icon works but a designed asset is recommended).
- [ ] Disable `usesCleartextTraffic` and point base URLs at production HTTPS/WSS.
- [ ] Flip `AppContainer.callService` to `WebRtcCallService` and validate
      against the live SFU; render `SurfaceViewRenderer`s for local/remote tracks.
- [ ] Add a privacy policy + data-safety declarations (camera, mic, contacts).
```

---

## Notes for maintainers

- The system `java` may be absent; **always** `export JAVA_HOME` before Gradle.
- Kotlin compilation is set to `in-process` (`gradle.properties`) for stable
  builds in sandboxed/CI shells; remove for faster local incremental builds with
  the Kotlin daemon.
- `keystore.properties`, `*.jks`, `local.properties`, and the Play
  service-account JSON are gitignored — never commit secrets.
