# SFU media protocol

The SFU media socket is reached at `sfuUrl` =
`wss://<sfu-node>/ws?room=<roomId>&token=<joinToken>`. The `joinToken` is a
short-lived JWT minted by the control plane (`/calls` or `/calls/:id/accept`)
under the shared `SFU_JWT_SECRET`; the SFU validates it and that its `room_id`
matches the query before upgrading.

## Messages (JSON, `{ "type": ... }`)

Client → SFU:
- `offer { sdp }` — client publishes its tracks + asks to subscribe. SFU replies `answer`.
- `answer { sdp }` — reply to an SFU-initiated renegotiation `offer`.
- `ice { candidate, sdpMid?, sdpMlineIndex? }` — trickled ICE.
- `ping`.

SFU → client:
- `answer { sdp }` — answer to the client's offer.
- `offer { sdp }` — SFU-initiated offer when new remote tracks were added (a new
  participant published) → client must reply `answer`.
- `ice { candidate, sdpMid, sdpMlineIndex }`.
- `peer_joined { userId }`, `peer_left { userId }`.
- `pong`, `error { message }`.

## Flow

1. Client gets `joinToken` + `sfuUrl` + `iceServers` from the control plane.
2. Client builds an `RTCPeerConnection` with those `iceServers`, adds its
   mic/cam tracks, creates an offer, sends `offer`.
3. SFU sets remote, attaches forwarding tracks for media already in the room,
   answers. Media flows.
4. When another participant publishes, the SFU adds that forwarding track to
   each existing peer and sends them an `offer`; they reply `answer`.
5. RTP from each publisher's uplink is pumped into per-subscriber local tracks
   (one uplink in, many downlinks out). Simulcast layer selection slots in here.
