# Face photo licenses

The JPEGs in this directory stand in for real profile photos when
`capture_screenshots.sh` launches the app with `-mockPhotosDir` (see
`ios/Sources/DesignSystem/MockPhotoAvatars.swift`), so the App Store
screenshots show a real-looking video-call frame instead of initials or
placeholders.

**As of September 2026 these are real, licensed photographs of real
people**, replacing an earlier AI-generated ("StyleGAN2 / this-person-does-
not-exist" style) set that had gotten visibly bad, including a machine-
generated watermark burned into at least one image. Every photo below was
sourced from Flickr via [Openverse](https://openverse.org) (a search index
over Creative-Commons-licensed Flickr/Wikimedia Commons media), and every
license was confirmed by loading the photo's actual Flickr page, not just
trusted from Openverse's metadata. All are CC BY 2.0, so reuse (including
this commercial, compositing-into-App-Store-screenshots use) is permitted
provided the photographer is credited, which is what this file does.

None of the source pages show or suggest the subject is a minor; all read
as adult subjects in clearly posed/willing portrait or self-portrait
photography (studio headshots, or photographers' own self-portraits), not
candid/paparazzi shots of identifiable public figures.

Each image was center-cropped to a square (top-cropped for `daniela.jpg`,
to cut a photographer's watermark out of frame) and resized to 1024x1024
JPEG, matching the dimensions of the files they replace.

Only `self`, `maya`, `priya`, `grace`, `ben`, `leo`, and `isla` are wired
up to a `MockData` profile id today (see `fileByUserId` in
`MockPhotoAvatars.swift`); `alex`, `daniela`, and `tom` aren't referenced
by any id yet but are kept here, real and licensed, in case a future
`-scene` needs another profile.

| File | Title | Author | License | Source | Notes |
|---|---|---|---|---|---|
| `self.jpg` | "Tired, sunburned and recent Dan" | dancomehome | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/77325022@N05/8513820073 | Used for both the Profile tab avatar and the date screen's local self-view thumbnail (`u_me`). |
| `maya.jpg` | "Becky_Headshot-forPrint" | calypsocom | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/34864470@N05/9968940246 | `u_maya`. This is the profile photo actually visible in the composed `date`/`decision`/`match`/`chat` App Store screenshots (MockData's default partner). |
| `priya.jpg` | "black shirt smile" | Jen Knoedl (JenTravelsLife) | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/40648063@N06/14895102141 | `u_priya`. |
| `grace.jpg` | "ks 24" | Lauren Nelson / Sweet Carolina Photography | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/20255774@N05/3007707759 | `u_grace`. |
| `ben.jpg` | "May 27, 2011" | Jeremy Jenum | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/63947148@N00/5766145471 | `u_daniel` ("Daniel" in MockData; file predates that mapping). Black & white. |
| `leo.jpg` | "Gavin Llewellyn" | Gavin Llewellyn | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/53682558@N06/6072486493 | `u_marcus` ("Marcus" in MockData). Self-portrait. Black & white. |
| `isla.jpg` | "Mariah" | Walt Stoneburner | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/8404611@N06/3638237641 | `u_sam` ("Sam" in MockData, nonbinary; file predates that mapping). |
| `alex.jpg` | "Victoria" | Paul Stevenson | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/53496815@N00/5000081948 | Not currently mapped to a MockData id. Black & white. |
| `daniela.jpg` | "Professional Headshot Woman San Antonio Texas 210-541-2985" | Richard Rives / Richard's Photography San Antonio | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/7587144@N04/39842305891 | Not currently mapped to a MockData id. Top-cropped to remove the studio's watermark. |
| `tom.jpg` | "#autorretrato #beardlifestyle #blackandwhite #bw" | nachosmooth | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) | https://www.flickr.com/photos/64821346@N00/17208582423 | Not currently mapped to a MockData id. Self-portrait (`#autorretrato`). Black & white. |

All images are licensed **CC BY 2.0**: https://creativecommons.org/licenses/by/2.0/
— attribution is the only condition, and it's captured in this table (each
row's Author + Source link). No CC0 photos were used because none of the
CC0 candidates found were a good fit for "candid video-call framing,
looking at camera, good lighting"; no NC or ND licensed photos were
considered.

## Sourcing method

Photos were found via the [Openverse](https://openverse.org) API
(`api.openverse.org/v1/images`, filtered to `license=cc0,by`, mostly
`source=flickr`), which aggregates Creative-Commons-licensed Flickr and
Wikimedia Commons photos and surfaces each photo's license, author, and
original Flickr/Commons URL. For every photo used here, that Flickr URL
was independently loaded to confirm the CC BY 2.0 badge before download,
rather than trusting Openverse's indexed metadata alone. A few Openverse
hits were rejected during this process: one candidate (originally slated
for `tom.jpg`) had its Flickr photo page return 404 since being indexed,
so its license could no longer be confirmed and it was dropped in favor of
`nachosmooth`'s self-portrait above.
