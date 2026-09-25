-- Up Migration
-- How the admin links the number: scanning a QR code or entering a pairing code on the phone.
ALTER TABLE wadesk_engine.sessions
  ADD COLUMN link_method text NOT NULL DEFAULT 'qr' CHECK (link_method IN ('qr', 'code'));

-- Down Migration
ALTER TABLE wadesk_engine.sessions DROP COLUMN link_method;
