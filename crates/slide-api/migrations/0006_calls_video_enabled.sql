-- Persist the caller's media choice and presentation so every client joins and
-- rings with the same audio/video/knock mode.
ALTER TABLE calls
    ADD COLUMN IF NOT EXISTS video_enabled BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE calls
    ADD COLUMN IF NOT EXISTS ring_style TEXT NOT NULL DEFAULT 'call';
