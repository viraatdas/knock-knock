# Store assets — specs & shot list

The visual identity is `docs/DESIGN.md`: pure white, thin near-black type, one
restrained accent. Assets should feel calm and premium — lots of white space.

## App icon
- A single, minimal mark on white: a thin "S" / a subtle forward-slide glyph.
- iOS: 1024×1024 PNG (no alpha, no rounded corners — Apple rounds it).
- Android: adaptive icon — 108×108dp foreground (the mark) + solid white
  background layer; provide `ic_launcher_foreground` (vector) + white background.
- Keep ≥ 20% padding; the mark should be small and centered, not edge-to-edge.

## Screenshots (the shot list — all on pure white)
Capture these five, which tell the product story:
1. **Welcome** — the thin "Slide" wordmark + "Get started".
2. **Enter phone** — "We'll text you a code." (the frictionless signup).
3. **Recents** — a clean call list (use seeded demo data, not real numbers).
4. **Contacts → contact sheet** — the two thin call buttons.
5. **In-call** — full-bleed video with the minimal control row.

### Required sizes
- **iOS** (App Store Connect): 6.7" (1290×2796) and 6.5" (1242×2688) iPhone.
  fastlane `snapshot` can generate these from a UI test plan.
- **Android** (Play): phone screenshots 1080×1920+ (min 2, max 8), plus a
  **feature graphic** 1024×500 (thin "Slide" wordmark centered on white).

## Already captured
- `android/screenshots/01-welcome.png`, `android/screenshots/02-enter-phone.png`
  (real captures from the running Android app — reuse as listing screenshots /
  brand reference).

## How they're generated
- iOS: `fastlane snapshot` drives the simulator through the five screens.
- Android: `fastlane screengrab`, or capture via the emulator and drop PNGs in
  `android/fastlane/metadata/android/en-US/images/phoneScreenshots`.
