# Custom ringtone (iOS)

Slide plays a custom **incoming-call ringtone** through CallKit. To set it, drop
one audio file here:

    ios/Resources/ringtone.caf

`CallKitManager` (see `Sources/Services/CallKitManager.swift`) auto-detects that
file and sets `CXProviderConfiguration.ringtoneSound = "ringtone.caf"`. If the
file is absent, the system default ring is used — so the app ships fine without it.

## Format requirements (Apple)
- Container: **CAF** (Core Audio Format) is the most reliable for CallKit; AIFF
  also works. Keep it short (a 30s loopable clip is typical).
- Convert any source file with afconvert:

      afconvert input.m4a ringtone.caf -d ima4 -f caff -v

## ⚠️ Licensing — important
Do NOT bundle copyrighted music (e.g. a track ripped from YouTube). Apple will
reject the app, and it's a rights violation. Use audio you own, have licensed,
or that is royalty-free / Creative-Commons-cleared for app distribution. Once you
have a rights-cleared file, convert it to `ringtone.caf`, place it here, rebuild,
and CallKit will use it automatically.
