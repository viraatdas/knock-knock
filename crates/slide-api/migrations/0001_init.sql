-- Slide initial schema.
-- Phone is the identity; everything hangs off the users table.

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- gen_random_uuid()

-- ── Enums ────────────────────────────────────────────────────────────────────
CREATE TYPE platform          AS ENUM ('ios', 'android');
CREATE TYPE call_type         AS ENUM ('one_to_one', 'group');
CREATE TYPE call_status       AS ENUM ('ringing', 'active', 'ended', 'missed', 'declined');
CREATE TYPE participant_state AS ENUM ('invited', 'ringing', 'joined', 'left', 'declined');

-- ── Users ────────────────────────────────────────────────────────────────────
CREATE TABLE users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone        TEXT NOT NULL UNIQUE,            -- E.164
    display_name TEXT,
    avatar_url   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_phone ON users (phone);

-- ── Devices ──────────────────────────────────────────────────────────────────
CREATE TABLE devices (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    push_token  TEXT NOT NULL UNIQUE,
    platform    platform NOT NULL,
    app_version TEXT NOT NULL DEFAULT '',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user ON devices (user_id);

-- ── Contacts ─────────────────────────────────────────────────────────────────
CREATE TABLE contacts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id   UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES users (id) ON DELETE SET NULL,
    phone           TEXT NOT NULL,                 -- E.164
    display_name    TEXT NOT NULL DEFAULT '',
    UNIQUE (owner_user_id, phone)
);
CREATE INDEX idx_contacts_owner ON contacts (owner_user_id);

-- ── Calls ────────────────────────────────────────────────────────────────────
CREATE TABLE calls (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id     TEXT NOT NULL,
    sfu_node_id TEXT NOT NULL,
    type        call_type NOT NULL,
    created_by  UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status      call_status NOT NULL DEFAULT 'ringing',
    started_at  TIMESTAMPTZ,
    ended_at    TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_calls_created_by ON calls (created_by);
CREATE INDEX idx_calls_created_at ON calls (created_at DESC);

-- ── Call participants ────────────────────────────────────────────────────────
CREATE TABLE call_participants (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id   UUID NOT NULL REFERENCES calls (id) ON DELETE CASCADE,
    user_id   UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    state     participant_state NOT NULL DEFAULT 'invited',
    joined_at TIMESTAMPTZ,
    left_at   TIMESTAMPTZ,
    UNIQUE (call_id, user_id)
);
CREATE INDEX idx_participants_call ON call_participants (call_id);
CREATE INDEX idx_participants_user ON call_participants (user_id);

-- ── Refresh tokens (opaque, rotated, hash-only) ──────────────────────────────
CREATE TABLE refresh_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    device_id  UUID REFERENCES devices (id) ON DELETE SET NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_user ON refresh_tokens (user_id);
