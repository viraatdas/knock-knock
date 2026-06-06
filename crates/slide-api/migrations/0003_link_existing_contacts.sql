-- Link address-book contacts that were synced before the matching Slide
-- account existed. The runtime contact list also read-repairs this case, but
-- this migration fixes existing production rows as soon as it deploys.
UPDATE contacts c
SET contact_user_id = u.id
FROM users u
WHERE c.contact_user_id IS NULL
  AND c.phone = u.phone
  AND u.id <> c.owner_user_id;
