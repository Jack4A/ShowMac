-- Anonymous aggregate counters. Reapplying this schema never resets totals.
CREATE TABLE IF NOT EXISTS stats_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT OR IGNORE INTO stats_meta (key, value)
VALUES ('started_at', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));

CREATE TABLE IF NOT EXISTS stats_counters (
  kind TEXT NOT NULL CHECK (kind IN ('pageview', 'download')),
  bucket TEXT NOT NULL,
  count INTEGER NOT NULL CHECK (count >= 0),
  PRIMARY KEY (kind, bucket)
);
CREATE TABLE IF NOT EXISTS stats_events (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('pageview', 'download')),
  bucket TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS stats_events_expiry ON stats_events (created_at);

-- One insert atomically deduplicates retries and increments its aggregate.
CREATE TRIGGER IF NOT EXISTS stats_increment AFTER INSERT ON stats_events
BEGIN
  INSERT INTO stats_counters (kind, bucket, count)
  VALUES (NEW.kind, NEW.bucket, 1)
  ON CONFLICT (kind, bucket) DO UPDATE SET count = count + 1;
  -- Retain retry IDs for seven days; aggregate totals are kept indefinitely.
  DELETE FROM stats_events WHERE created_at < NEW.created_at - 604800;
END;
