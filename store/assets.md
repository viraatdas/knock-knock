# Store assets: specs and shot list (iOS, Knock Knock - 5 Minute Dates)

The visual identity moved from the old pure-white minimal look to a warm
palette: eggshell ground, espresso ink, terracotta accent (`#D4694F`). See
`AGENTS.md` and `ios/Sources/DesignSystem/Theme.swift` for the exact tokens.
Assets should read as warm and calm, not corporate. This file covers iOS;
Android is frozen at the old product and isn't part of this pivot.

## App icon
`ios/tools/make_appicon.py` generates `icon-1024.png` from a single motif: a
rounded espresso door with a terracotta heart as the knocker (or two
overlapping speech-bubble hearts "knocking"). No text, no thin strokes that
disappear at 60px, no loud gradients.
- iOS: 1024×1024 PNG, no alpha, no rounded corners (Apple rounds it itself).
- Same source also exports to `web/public/apple-touch-icon.png` (180×180) and
  `web/public/icon.svg` / `favicon.svg`.

## Screenshots (the shot list)
Six screens tell the story, captured from the real app's mock-data scenes
(`Config.useMockData`, launch arg `-scene <name>`), not staged photos:

1. **Tonight, closed** (`tonightClosed`): the countdown to 7 PM, calm and
   quiet.
2. **Lobby** (`lobby`): "Finding someone nearby…" with the breathing circle.
3. **Date** (`date`): the video date in progress, countdown ring visible.
4. **Decision** (`decision`): "Keep talking with Maya?" with the two
   buttons.
5. **Match** (`match`): "It's a match" with the partner card.
6. **Chat** (`chat`): a real-looking message thread.

Each screenshot gets a short caption band composited on top by
`ios/tools/compose_screenshots.py`: eggshell band, espresso text, one line
per screen (for example "Five minutes. One person. No swiping." for the Date
screen). This replaces the old raw-scene screenshot generator.

### Required sizes
- **6.9":** 1320×2868 (iPhone 17 Pro Max) or the equivalent App Store
  Connect accepts for the largest device size.
- **6.5":** 1290×2796 variant.
- Generate both from the same six scenes; don't hand-design separate art per
  size.

## How they're generated
1. Build and run the app in the simulator with `-scene <name>` for each of
   the six screens above.
2. Screenshot each with `xcrun simctl io <udid> screenshot`.
3. Run `ios/tools/compose_screenshots.py` to add the caption band and produce
   both size variants.
4. Drop the results in `ios/fastlane/screenshots/en-US/` (or wherever
   `fastlane deliver` expects them) for upload.

## Already captured
The old Android screenshots (`android/screenshots/01-welcome.png`,
`02-enter-phone.png`) are from the pre-pivot calling app and shouldn't be
reused here. They're still fine as Android reference since Android hasn't
moved to the new product yet.
