CREATE INDEX IF NOT EXISTS idx_contacts_owner_unlinked_phone
ON contacts (owner_user_id, phone)
WHERE contact_user_id IS NULL;
