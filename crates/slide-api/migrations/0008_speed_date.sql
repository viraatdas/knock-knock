-- Pivot to Knock Knock Speed Date: profile/preferences on users, the nightly
-- lobby/date/match/chat schema, safety tables, and removal of the legacy
-- calling product (calls, call_participants, contacts). Runs cleanly on a
-- fresh DB (after 0001-0007) and on the production DB with old rows.

-- Profile + preferences on users
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS birthdate DATE,
  ADD COLUMN IF NOT EXISTS gender TEXT,                      -- 'woman' | 'man' | 'nonbinary'
  ADD COLUMN IF NOT EXISTS interested_in TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS age_min SMALLINT NOT NULL DEFAULT 18,
  ADD COLUMN IF NOT EXISTS age_max SMALLINT NOT NULL DEFAULT 99,
  ADD COLUMN IF NOT EXISTS bio TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS photo BYTEA,                      -- JPEG, client-resized, <= 600 KB
  ADD COLUMN IF NOT EXISTS photo_updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS profile_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_review_account BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE lobby (
  user_id      UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,                 -- PT calendar date of the session
  joined_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE dates (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  room_id      TEXT NOT NULL,                 -- = id as string; LiveKit room name
  session_date DATE NOT NULL,
  started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at      TIMESTAMPTZ NOT NULL,          -- started_at + DATE_SECONDS
  ended_at     TIMESTAMPTZ,
  end_reason   TEXT,                          -- 'timeout' | 'left' | 'blocked'
  decision_a   BOOLEAN, decided_a_at TIMESTAMPTZ,
  decision_b   BOOLEAN, decided_b_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_dates_user_a ON dates (user_a, session_date);
CREATE INDEX idx_dates_user_b ON dates (user_b, session_date);
CREATE INDEX idx_dates_open ON dates (ends_at) WHERE ended_at IS NULL;

CREATE TABLE matches (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date_id         UUID REFERENCES dates(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_message_at TIMESTAMPTZ,
  unmatched_at    TIMESTAMPTZ,
  unmatched_by    UUID,
  CHECK (user_a < user_b),
  UNIQUE (user_a, user_b)
);
CREATE INDEX idx_matches_user_a ON matches (user_a);
CREATE INDEX idx_matches_user_b ON matches (user_b);

CREATE TABLE messages (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id   UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  sender_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body       TEXT NOT NULL,                   -- 1..2000 chars after trim, text only
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_match_created ON messages (match_id, created_at DESC);

CREATE TABLE match_reads (
  match_id     UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, user_id)
);

CREATE TABLE blocks (
  blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason      TEXT NOT NULL,                  -- 'inappropriate' | 'harassment' | 'fake' | 'underage' | 'other'
  details     TEXT NOT NULL DEFAULT '',
  date_id     UUID, match_id UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Legacy calling product is gone.
DROP TABLE IF EXISTS call_participants;
DROP TABLE IF EXISTS calls;
DROP TABLE IF EXISTS contacts;
DROP TYPE IF EXISTS participant_state;
DROP TYPE IF EXISTS call_status;
DROP TYPE IF EXISTS call_type;
DELETE FROM push_subscriptions WHERE kind <> 'apns';   -- only standard APNs alert tokens remain
