-- New signups link any existing address-book rows for their phone. Keep that
-- lookup cheap as the contacts table grows.
CREATE INDEX IF NOT EXISTS idx_contacts_unlinked_phone
ON contacts (phone)
WHERE contact_user_id IS NULL;
