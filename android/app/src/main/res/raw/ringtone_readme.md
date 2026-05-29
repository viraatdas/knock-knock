# Ringtone (optional custom sound)

Drop a `ringtone.<ext>` audio file (e.g. `ringtone.ogg` / `ringtone.mp3`) in this
folder to enable Slide's custom incoming-call sound. Wiring is automatic — see
`SlideConnectionService.ringtoneUri()`:

- If a `res/raw/ringtone` resource exists at build time it is used for incoming calls.
- If it is absent, Slide falls back to the system default `TYPE_RINGTONE`.

Note: Android resource filenames must be lowercase, so this doc is named
`ringtone_readme.md` (it is never referenced by code). The build is green with no
audio file present.
