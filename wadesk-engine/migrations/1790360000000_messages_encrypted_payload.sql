-- Up Migration
-- Media metadata includes WhatsApp media keys, so it is stored encrypted like credentials (ADR-0004).
-- The table has held no data yet, so the plaintext column is simply replaced.
ALTER TABLE wadesk_engine.messages DROP COLUMN meta;
ALTER TABLE wadesk_engine.messages ADD COLUMN payload bytea NOT NULL;

-- Down Migration
ALTER TABLE wadesk_engine.messages DROP COLUMN payload;
ALTER TABLE wadesk_engine.messages ADD COLUMN meta jsonb NOT NULL DEFAULT '{}';
