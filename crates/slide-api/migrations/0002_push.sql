-- Push subscriptions for offline ring (incoming call / escalated knock).
--
-- DESIGN: a brand-new table that does NOT use the `platform` enum from 0001.
-- Rationale: extending a Postgres enum (`ALTER TYPE ... ADD VALUE 'web'`)
-- cannot run inside a transaction, and sqlx::migrate! runs every migration in
-- a transaction. Rather than fight that, push tokens live in their own table
-- keyed by (user_id, token) with a free-text `kind` discriminator
-- ('apns_voip' | 'fcm' | 'webpush'). The existing `devices` table + endpoint
-- keep working untouched.
--
-- For Web Push the subscription is more than a single token (endpoint + p256dh
-- + auth keys), so `token` holds the endpoint URL and `p256dh` / `auth` hold
-- the Web Push keys (NULL for APNs/FCM).

CREATE TABLE push_subscriptions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind        TEXT NOT NULL,                      -- 'apns_voip' | 'fcm' | 'webpush'
    token       TEXT NOT NULL,                      -- device token, or Web Push endpoint URL
    p256dh      TEXT,                               -- Web Push: client public key (base64url)
    auth        TEXT,                               -- Web Push: client auth secret (base64url)
    app_version TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, token)
);
CREATE INDEX idx_push_subs_user ON push_subscriptions (user_id);
