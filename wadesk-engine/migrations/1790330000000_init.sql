-- Up Migration
-- Engine state lives in its own schema inside the Chatwoot database (docs/wadesk/02-architecture.md §5).

-- One row per WhatsApp Web inbox. id = Chatwoot Channel::Whatsapp id.
CREATE TABLE wadesk_engine.sessions (
  id             text PRIMARY KEY,
  expected_phone text NOT NULL,
  webhook_url    text NOT NULL,
  state          text NOT NULL DEFAULT 'created',
  me_jid         text,
  me_lid         text,
  last_error     text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Baileys credentials and Signal keys, encrypted by the engine (ADR-0004).
-- category = 'creds' or a Signal key type; key_id = '' for creds.
CREATE TABLE wadesk_engine.auth_keys (
  session_id text NOT NULL REFERENCES wadesk_engine.sessions (id) ON DELETE CASCADE,
  category   text NOT NULL,
  key_id     text NOT NULL,
  value      bytea NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, category, key_id)
);

-- Metadata needed for media download and quoted replies; no text bodies. Pruned after 30 days.
CREATE TABLE wadesk_engine.messages (
  session_id text NOT NULL REFERENCES wadesk_engine.sessions (id) ON DELETE CASCADE,
  message_id text NOT NULL,
  meta       jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, message_id)
);
CREATE INDEX messages_created_at_idx ON wadesk_engine.messages (created_at);

-- Events waiting to be delivered to Chatwoot. No FK: a session's final events
-- (e.g. logged_out) must still be delivered after the session row is deleted.
CREATE TABLE wadesk_engine.outbox (
  id              bigserial PRIMARY KEY,
  session_id      text NOT NULL,
  payload         jsonb NOT NULL,
  attempts        integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX outbox_due_idx ON wadesk_engine.outbox (next_attempt_at, id);

-- Down Migration
DROP TABLE wadesk_engine.outbox;
DROP TABLE wadesk_engine.messages;
DROP TABLE wadesk_engine.auth_keys;
DROP TABLE wadesk_engine.sessions;
