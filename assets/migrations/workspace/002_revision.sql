ALTER TABLE client_engagements
  ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0);
