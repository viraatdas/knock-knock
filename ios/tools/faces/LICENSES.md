# Face photos: provenance

The JPEGs in this directory stand in for real profile photos when
`capture_screenshots.sh` launches the app with `-mockPhotosDir` (see
`ios/Sources/DesignSystem/MockPhotoAvatars.swift`), so the App Store
screenshots show a real-looking video-call frame instead of initials or
placeholders.

**As of September 2026 these are AI-generated images of people who do not
exist.** They replace an earlier set of real, CC BY 2.0-licensed Flickr
photos (see git history / this file's prior version) that the app's owner
felt looked too much like posed studio headshots and not enough like a
casual phone video-call frame — the actual screen these photos appear on.

Each was generated with OpenAI's image generation (via the Codex CLI's
built-in `image_gen` tool, ChatGPT-authenticated) on 2026-09-14, with a
prompt asking for a natural, everyday, candid "on a video call" photo:
imperfect phone-camera framing, non-studio lighting, a genuine (not
camera-ready) expression, in an ordinary home setting. No prompt asked for
or optimized toward conventional attractiveness — the brief was specifically
"natural, not idealized," to fix the mismatch with the studio-headshot set
before it, not to repeat the earlier StyleGAN2 set's problem of looking
synthetic in a different way (that original set, replaced 2026-09-14
morning, had a machine-generated watermark burned into one image).

None of these people are real; each was generated fresh for this app and
does not depict, or intend to depict, any specific real person, living or
dead. No consent/likeness question applies the way it would for a real
photo, and no attribution is owed (contrast with the CC BY set this
replaced, which did require it).

| File | Used for | Notes |
|---|---|---|
| `self.jpg` | `u_me` — Profile avatar + the date screen's local self-view thumbnail | |
| `maya.jpg` | `u_maya` | The profile photo actually visible in the composed `date`/`decision`/`match`/`chat` App Store screenshots (MockData's default partner). |
| `priya.jpg` | `u_priya` | |
| `grace.jpg` | `u_grace` | |
| `ben.jpg` | `u_daniel` ("Daniel" in MockData; file predates that mapping) | |
| `leo.jpg` | `u_marcus` ("Marcus" in MockData) | |
| `isla.jpg` | `u_sam` ("Sam" in MockData, nonbinary; file predates that mapping) | |
| `alex.jpg` | Not currently mapped to a MockData id | Spare, kept for a future scene. |
| `daniela.jpg` | Not currently mapped to a MockData id | Spare, kept for a future scene. |
| `tom.jpg` | Not currently mapped to a MockData id | Spare, kept for a future scene. |

Only `self.jpg` and `maya.jpg` currently appear in the composed App Store
screenshots (the `date`/`decision`/`match`/`chat` scenes all default to
MockData's "maya" partner); the rest exist for completeness / future
`-scene` additions.
