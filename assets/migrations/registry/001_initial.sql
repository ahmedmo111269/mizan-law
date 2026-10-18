CREATE TABLE people (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('natural', 'organization')),
  display_name TEXT NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 200),
  name_normalized TEXT NOT NULL,
  phone TEXT,
  phone_normalized TEXT,
  email TEXT,
  email_normalized TEXT,
  created_at_utc TEXT NOT NULL,
  updated_at_utc TEXT NOT NULL
);

CREATE INDEX idx_people_name_prefix
  ON people (name_normalized, id);

CREATE INDEX idx_people_phone
  ON people (phone_normalized)
  WHERE phone_normalized IS NOT NULL;

CREATE INDEX idx_people_email
  ON people (email_normalized)
  WHERE email_normalized IS NOT NULL;
