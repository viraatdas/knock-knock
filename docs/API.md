# Slide API contract (v1)

Base URL: `/v1`. All JSON. Auth via `Authorization: Bearer <accessToken>` except
the auth endpoints. Errors use a consistent envelope:

```json
{ "error": { "code": "rate_limited", "message": "too many requests", "retryAfter": 30 } }
```

Field casing is **camelCase** on the wire.

## Auth (phone-only)

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/auth/request-otp` | `{ "phone": "+14155550123" }` | `202` (in dev, also `{ "devCode": "123456" }`) |
| POST | `/auth/verify-otp` | `{ "phone", "code" }` | `{ "accessToken", "refreshToken", "isNewUser", "user" }` |
| POST | `/auth/refresh` | `{ "refreshToken" }` | `{ "accessToken", "refreshToken" }` |
| POST | `/auth/logout` | `{ "refreshToken" }` | `204` |

## User & onboarding (auth required)

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/me` | — | `User` |
| PATCH | `/me` | `{ "displayName"?, "avatarUrl"? }` | `User` |
| POST | `/me/avatar` | multipart `file` | `{ "avatarUrl" }` |
| POST | `/devices` | `{ "pushToken", "platform", "appVersion" }` | `Device` |

## Contacts (auth required)

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/contacts/sync` | `{ "phones": ["+1..."] }` | `[{ "phone", "displayName", "userId"?, "onSlide" }]` |
| GET | `/contacts` | — | `[Contact]` |

## Calls — control plane (auth required)

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/calls` | `{ "type": "one_to_one"\|"group", "participantUserIds": [] }` | `{ "call", "joinToken", "sfuUrl", "iceServers" }` |
| POST | `/calls/:id/accept` | — | `{ "call", "joinToken", "sfuUrl", "iceServers" }` |
| POST | `/calls/:id/decline` | — | `204` |
| POST | `/calls/:id/leave` | — | `204` |
| GET | `/calls?cursor=` | — | `{ "calls": [Call], "nextCursor"? }` |

## Realtime plane A — app signaling: `GET /v1/ws?token=<accessToken>`

Server → client events (JSON `{ "type", ... }`):
`incoming_call`, `call_accepted`, `call_declined`, `call_ended`,
`participant_joined`, `participant_left`, `presence_update`.

Client → server: `presence_ping`, `heartbeat`.

## Realtime plane B — SFU media: `sfuUrl` (separate node)

Authenticated by the room-scoped `joinToken`. Carries SDP offer/answer + ICE
trickle + per-publisher track subscription. See `docs/SFU.md`.

## Models (camelCase JSON)

```
User          { id, phone, displayName?, avatarUrl?, createdAt, lastSeenAt }
Device        { id, userId, pushToken, platform, appVersion, updatedAt }
Contact       { id, ownerUserId, contactUserId?, phone, displayName }
Call          { id, roomId, sfuNodeId, type, createdBy, status, startedAt?, endedAt?, createdAt,
                participants: [{ userId, state, joinedAt?, leftAt? }] }
IceServer     { urls: [], username?, credential? }
```

`platform` ∈ `ios|android`. `type` ∈ `one_to_one|group`.
`call.status` ∈ `ringing|active|ended|missed|declined`.
`participant.state` ∈ `invited|ringing|joined|left|declined`.
