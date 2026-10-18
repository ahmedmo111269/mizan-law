CREATE TABLE workspaces (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
  file_name TEXT NOT NULL UNIQUE,
  created_at_utc TEXT NOT NULL
);

CREATE TABLE catalog_settings (
  setting_key TEXT PRIMARY KEY NOT NULL,
  setting_value TEXT NOT NULL
);
