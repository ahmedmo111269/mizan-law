CREATE TABLE client_engagements (
  id TEXT PRIMARY KEY NOT NULL,
  person_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'archived')),
  created_at_utc TEXT NOT NULL,
  updated_at_utc TEXT NOT NULL,
  status_changed_at_utc TEXT NOT NULL,
  UNIQUE (person_id)
);

CREATE INDEX idx_client_engagements_status_updated
  ON client_engagements (status, updated_at_utc DESC, id);

CREATE TABLE operation_receipts (
  operation_id TEXT PRIMARY KEY NOT NULL,
  engagement_id TEXT NOT NULL,
  completed_at_utc TEXT NOT NULL,
  FOREIGN KEY (engagement_id)
    REFERENCES client_engagements (id)
    ON DELETE RESTRICT
);
