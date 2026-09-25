-- Up Migration
-- The target URL travels with each event, so final events (e.g. logged_out) are still
-- delivered after their session row is deleted.
ALTER TABLE wadesk_engine.outbox ADD COLUMN webhook_url text NOT NULL;

-- Down Migration
ALTER TABLE wadesk_engine.outbox DROP COLUMN webhook_url;
