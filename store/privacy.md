# Privacy disclosures (App Store Privacy "Nutrition Label")

Knock Knock - 5 Minute Dates collects more than the old calling app did, because
matching people up for a video date needs a bit more than a phone number.
Below is what the backend actually stores (see `AGENTS.md` and the dates/chat
routes) and how that maps to Apple's nutrition-label categories. Keep this in
sync with the code whenever a profile field changes.

## Data collected

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Phone number | Yes | Yes | No | Account identity and sign-in |
| Name | Yes | Yes | No | Display name shown to your dates and matches |
| Photos | Yes (optional) | Yes | No | Profile photo shown to your dates and matches |
| Sensitive info (gender, who you want to see) | Yes | Yes | No | Matching you with people you're interested in |
| Coarse location | Yes | Yes | No | Finding dates within 75 miles; stored rounded to about a kilometer |
| Messages | Yes | Yes | No | Chat with a match, after a mutual match |
| User ID | Yes | Yes | No | App functionality (sessions, matches, reports) |
| Precise location | No | n/a | n/a | n/a |
| Payment info | No | n/a | n/a | n/a |
| Audio/video content | No (not stored) | n/a | n/a | Dates are real-time video, the call itself is never recorded |
| Advertising or third-party tracking data | No | n/a | n/a | n/a |

Every category above is declared as **App Functionality**, not advertising or
analytics, and none of it is used to track users across other companies' apps
or sites.

## What we actually collect and why
- **Phone number.** How you sign in. No email, no password.
- **Name, birthdate, gender, and who you want to see.** Set during profile
  setup, used to figure out who you can date and to check you're 18 or older.
  We store birthdate and show your age, not the birthdate itself, to your
  dates and matches.
- **Bio.** Optional, up to 300 characters, shown to your dates and matches.
- **Photo.** Optional. Shown to your dates and matches; not shown to anyone
  you've blocked or who's blocked you.
- **Location.** Rounded to about a kilometer before it's stored, used only to
  find people within 75 miles and to show an approximate distance. We don't
  store or show your exact location.
- **Messages.** Text only, between two people who both said keep talking to
  each other. No photos or attachments in chat.
- **Reports and blocks.** If you report or block someone, we keep a record so
  we can act on it and so a blocked person can't match with you again.

## Key statements (true to the implementation)
- **No email, no password.** Identity is a verified phone number only.
- **Video dates are not recorded.** The call is real-time and isn't saved on
  our servers.
- **No third-party advertising SDKs. No tracking across other apps or sites.**
- **Account deletion** is in the app, under Profile > Delete account. It
  removes the account and everything tied to it (profile, matches, messages,
  reports you filed) right away.
- **Retention.** We keep your data as long as your account exists. Deleting
  your account deletes it. Reports you're the *subject* of may be kept longer
  for safety review even after the reporting user's data is otherwise gone.

## Encryption
- All API, WebSocket, and video-date traffic runs over TLS (HTTPS/WSS, and
  DTLS-SRTP for the video itself).
- Tokens are stored in Keychain on iOS.
- Video dates are not end-to-end encrypted; media is relayed through our
  LiveKit infrastructure, encrypted in transit. Be accurate on the store
  forms, don't claim end-to-end encryption.
