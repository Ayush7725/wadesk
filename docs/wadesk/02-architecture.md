# 02 — Architecture: WhatsApp Web channel

**Status:** Approved (Gate A, 2026-09-25) · **Last updated:** 2026-09-25 · Implements [01-requirements.md](01-requirements.md)

## 1. Overview

```
                       ┌──────────────────────────── WaDesk (one repo, one deployment) ───────────────────────────┐
                       │                                                                                             │
  Agent browser ──────▶│  Chatwoot Rails (web)  ──┐                                                                  │
                       │   • Channel::Whatsapp     │ REST (Bearer token)        ┌───────────────────────────┐        │
                       │     provider=baileys      ├───────────────────────────▶│  wadesk-engine (Node/TS)  │◀──────▶│── WhatsApp
                       │   • Webhooks::            │                             │   • Baileys sessions      │  WS    │   servers
                       │     WhatsappWebController │◀────────────────────────────│   • outbox dispatcher     │        │
                       │  Sidekiq (jobs)           │  Webhooks (HMAC-signed)     │   • media proxy           │        │
                       │                           │                             └────────────┬──────────────┘        │
                       │           └──────────────┬┘                                          │                       │
                       │                    ┌─────▼─────┐   schema `public` (Chatwoot)        │                       │
                       │                    │ Postgres  │◀────────────────────────────────────┘ schema `wadesk_engine` │
                       │                    └───────────┘                                                              │
                       └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Chatwoot** stays the system of record for accounts, inboxes, contacts, conversations and messages.
- **wadesk-engine** is an internal service that owns WhatsApp Web sockets. It holds no business logic: it
  translates between Baileys and a small, stable contract with Chatwoot.
- The Official channel (`whatsapp_cloud`) is untouched.

## 2. Components

### 2.1 wadesk-engine (`/wadesk-engine`)

| Concern | Choice |
|---|---|
| Runtime | Node 24 (same major as Chatwoot's frontend toolchain), TypeScript, ESM |
| HTTP | Fastify (schema-validated routes) |
| WhatsApp | `baileys` pinned to an exact version; upgrades via dedicated PRs |
| Storage | Postgres schema `wadesk_engine` in the Chatwoot database; migrations via `node-pg-migrate` |
| Logging | `pino` with redaction of message bodies, credentials and tokens |
| Tests | Vitest; Baileys socket mocked behind an adapter interface |
| Packaging | Own Dockerfile; runs as a compose service on the internal network only |

Internal modules:

- `SessionManager` — one `Session` per WhatsApp Web inbox, keyed by `sessionId` (= Chatwoot `Channel::Whatsapp#id`).
  Starts all sessions whose credentials exist at boot; isolates failures per session (WW-NFR-06).
- `Session` — wraps a Baileys socket: connect, QR/pairing code, reconnect with capped exponential backoff, logout.
  Verifies the linked number equals the expected number (WW-FR-04).
- `AuthStore` — Baileys `AuthenticationState` backed by Postgres, values encrypted with AES-256-GCM (ADR-0004).
- `SendLimiter` — per-session outgoing rate limit (SAFE-FR-03): excess messages wait in a queue. Plain throughput
  control only; no randomised "human" delays or other detection-evasion behaviour (ADR-0006).
- `Normalizer` — maps Baileys events to the Chatwoot contract (§4). Pure functions, fully unit-tested.
- `Outbox` + `Dispatcher` — every event bound for Chatwoot is first written to an outbox table, then delivered
  with retries; rows are deleted on 2xx. Guarantees at-least-once delivery across restarts (WW-FR-17, WW-NFR-02).
- `MessageStore` — keeps the raw message metadata needed for media download and quoted replies (30-day retention).
- `Metrics/Health` — `/health` (liveness + DB), `/metrics` (Prometheus text).

### 2.2 Chatwoot changes

New files (no upstream conflicts):

| File | Responsibility |
|---|---|
| `app/models/concerns/whatsapp_web_channel.rb` | Included in `Channel::Whatsapp`: plan gating (on create), default `link_method`, start engine session after create, remove it before destroy |
| `app/jobs/whatsapp_web/start_session_job.rb` | Starts/restarts the engine session in the background (retried by Sidekiq) |
| `app/services/whatsapp/providers/whatsapp_baileys_service.rb` | Provider: validates `link_method`; `sync_templates` only marks the sync (no templates on WhatsApp Web); `media_url`/`api_headers` point attachment downloads at the engine; `send_message` uploads text + first attachment + quote preview to the engine (rate limits and engine errors raise so `SendReplyJob` retries; other failures mark the message failed with an agent-facing reason) |
| `app/services/whatsapp_web/engine_client.rb` | Thin HTTP client for the engine API (auth header, timeouts, error mapping) |
| `app/services/whatsapp_web/session_lifecycle_service.rb` | Start / reconnect / logout / delete sessions |
| `app/controllers/webhooks/whatsapp_web_controller.rb` | Receives engine webhooks, verifies HMAC, routes events |
| `app/services/whatsapp_web/connection_update_service.rb` | Persists connection state on the channel (`provider_config.connection_state/reason/connected_phone`). Runs inline in the webhook request so events apply in the engine's order; admin notifications in M4.4 |
| `app/controllers/api/v1/accounts/whatsapp_web/sessions_controller.rb` | QR / pairing code / reconnect / logout for the UI |
| `app/services/wadesk/safety/new_chat_limit.rb` | Business-initiated chat cap for Web inboxes (SAFE-FR-02): rolling 24 h, default 20, operator override in `account.custom_attributes['wadesk_whatsapp_web_daily_new_chats']` (account admins cannot set it); checked in the provider before sending |
| `app/services/wadesk/safety/opt_out_detector.rb`, `app/listeners/wadesk/opt_out_listener.rb`, `app/models/wadesk/consent_event.rb` | Whole-message opt-out phrases (English, Hinglish, Hindi; operator override `WADESK_OPT_OUT_KEYWORDS`) on incoming WhatsApp messages → append-only `wadesk_consent_events` + activity note for agents (SAFE-FR-10/11) |
| `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappWeb.vue` (+ components) | Create inbox + QR panel |
| Specs under `spec/` mirroring the above | |

### Upstream touch points

Every edit to an existing Chatwoot file is listed here and kept minimal.

| File | Change |
|---|---|
| `app/models/channel/whatsapp.rb` | Add `baileys` to `PROVIDERS`; `provider_service` branch; `include WhatsappWebChannel` (lifecycle and gating live in the concern) |
| `app/services/conversations/message_window_service.rb` | No 24-hour window for `baileys` (WW-FR-24) |
| `config/routes.rb` | Engine webhook route + UI session routes |
| `config/features.yml` | Append `whatsapp_web` flag (`feature_flags_ext_1`) |
| `app/javascript/dashboard/featureFlags.js` | `WHATSAPP_WEB` constant |
| `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` | Offer "WhatsApp Web" provider when the flag is on |
| `app/javascript/dashboard/composables/useInbox.js` | `isAWhatsAppWebChannel` helper |
| `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` | New strings (other locales fall back to English) |
| `settings/inbox/settingsPage/ConfigurationPage.vue` | Connection panel for `baileys` inboxes |
| `docker-compose*.yaml`, `.env.example` | `wadesk-engine` service and its variables |
| Campaign creation (controller/service for WhatsApp campaigns) | Reject `baileys` inboxes (SAFE-FR-01) — exact file identified in M3 |
| `app/models/campaign.rb` | `include WhatsappWebCampaignGuard`: campaigns are rejected on WhatsApp Web inboxes (SAFE-FR-01) |
| `app/dispatchers/async_dispatcher.rb` | Registers `Wadesk::OptOutListener` |
| `db/migrate/*_create_wadesk_consent_events.rb`, `db/schema.rb` | `wadesk_consent_events` table |
| `config/locales/en.yml` | `wadesk.consent.*` strings |
| `lib/regex_helper.rb` | `WHATSAPP_CHANNEL_REGEX` also accepts WhatsApp Web privacy IDs (`<digits>@lid`) as contact source ids |
| `.github/` | Chatwoot-org-only workflows removed; `run_foss_spec.yml` manual-only; `wadesk_ci.yml` added; own PR template and CODEOWNERS |

Other provider-specific branches (templates, health, embedded signup, business token, CSAT templates, calling,
contact-info requests) check for `whatsapp_cloud` explicitly and skip `baileys` without changes — verified by
`spec/models/channel/whatsapp_web_channel_spec.rb` ("Cloud-only features", M2.6). Campaigns did **not**: the model accepted any WhatsApp
inbox, so `WhatsappWebCampaignGuard` rejects WhatsApp Web inboxes at creation.

## 3. Key flows

### 3.1 Connect a number (QR)

```
Admin UI           Chatwoot                          Engine                       WhatsApp
   │ create inbox     │                                  │                              │
   │─────────────────▶│ Channel::Whatsapp(provider=baileys, phone_number)               │
   │                  │ after_commit: PUT /sessions/:id ─▶ create Session, open socket ─▶│
   │ poll QR (2 s)    │                                  │◀──────── QR ref ──────────────│
   │─────────────────▶│ GET /sessions/:id ──────────────▶│ {state: qr_pending, qr}      │
   │◀── QR image ─────│                                  │                              │
   │ (phone scans)    │                                  │◀──── pair success (me.id) ───│
   │                  │                                  │ me.phone == expected? else logout + state=failed
   │                  │◀── webhook connection{connected}─│                              │
   │◀── "Connected" ──│ ConnectionUpdateService (inline) → provider_config.connection_state │
```

QR codes are never persisted; they are read live from the engine.

### 3.2 Incoming message

```
WhatsApp ─▶ Engine: messages.upsert
            ├─ drop if group / broadcast / status / newsletter (WW-FR-15)
            ├─ MessageStore.save(meta)             (for media + quotes)
            ├─ Normalizer → contract payload (§4.2)
            └─ Outbox.insert ─▶ Dispatcher ─▶ POST /webhooks/whatsapp_web/:channel_id (HMAC)
Chatwoot controller: verify HMAC (5-min replay window) → Webhooks::WhatsappEventsJob (existing, per-sender lock)
            └─ Whatsapp::IncomingMessageService (existing, unchanged: dedup by source_id, contact + conversation rules)
                 └─ attachments: channel.media_url → GET engine /sessions/:id/media/:message_id
```

### 3.3 Outgoing message

```
Agent reply ─▶ Message after_create_commit ─▶ SendReplyJob ─▶ SendOnWhatsappService (existing)
   └─ channel.send_message(contact_inbox.source_id, message)
        └─ WhatsappBaileysService ─▶ POST engine /sessions/:id/messages (multipart: to, text, reply_to, file)
             ◀─ { id }  → message.source_id
WhatsApp receipts ─▶ Engine messages.update ─▶ Outbox ─▶ webhook `statuses` ─▶ Messages::StatusUpdateService
```

## 4. Contracts

### 4.1 Engine API (called by Chatwoot)

Base URL `WADESK_ENGINE_URL` (internal). Header `Authorization: Bearer ${WADESK_ENGINE_API_TOKEN}`.

| Method & path | Purpose | Response |
|---|---|---|
| `PUT /sessions/:id` `{phone_number, webhook_url, link_method?}` | Create or restart a session (idempotent while live). `link_method`: `qr` (default) or `code` (ADR-0007) | `202 {state}` |
| `GET /sessions/:id` | Current state (+ live QR, or current pairing code in `code` mode, while pending) | `{state, qr?, pairing_code?, me?, last_error?}` |
| `DELETE /sessions/:id` | Log out and wipe credentials | `204` |
| `POST /sessions/:id/messages` (multipart: `to`, `text`, one `file`, `reply_to_id/text/from_me`) | Send text or one file, optionally quoting a message. Over 20/min per number → `429` + `Retry-After`; Chatwoot's send job retries (queued in Sidekiq, never dropped) | `201 {id}` |
| `GET /sessions/:id/media/:message_id` | Stream decrypted media | binary + `Content-Type`, `Content-Disposition` |
| `GET /health`, `GET /metrics` | Ops | |

Errors: JSON `{error: {code, message}}` with codes such as `session_not_found`, `not_connected`,
`invalid_recipient`, `media_expired`. The provider maps them to `message.external_error`.

### 4.2 Webhooks (engine → Chatwoot)

`POST /webhooks/whatsapp_web/:channel_id`, headers `X-WaDesk-Timestamp` and
`X-WaDesk-Signature: sha256=HMAC(secret, "#{timestamp}.#{body}")` (rejected if older than 5 minutes).

Message and status payloads deliberately use the **Cloud API shape already parsed by
`IncomingMessageBaseService`**, so contact/conversation/dedup logic is reused rather than rewritten:

```jsonc
// event: messages
{ "event": "messages",
  "contacts": [{ "wa_id": "919876543210", "user_id": "12345678@lid", "profile": { "name": "Ravi" } }],
  "messages": [{ "id": "3EB0C4...", "from": "919876543210", "timestamp": "1790000000",
                 "type": "image", "image": { "id": "3EB0C4...", "mime_type": "image/jpeg", "caption": "Price?" },
                 "context": { "id": "3EB0AA..." } }] }

// event: statuses
{ "event": "statuses", "statuses": [{ "id": "3EB0D1...", "status": "read", "recipient_id": "919876543210" }] }

// event: connection
{ "event": "connection", "state": "logged_out", "me": { "phone": "919812345678" }, "reason": "unlinked_from_phone" }
```

Identity mapping (WW-FR-14): `wa_id` is the phone number from `remoteJid` (`@s.whatsapp.net`) or, for
LID-addressed chats, from Baileys' `remoteJidAlt`. The LID goes into `user_id`. If no phone number is
available the message is still delivered with `wa_id` = LID and linked later when the number is learned.

## 5. Data

| Store | Owner | Contents |
|---|---|---|
| `channel_whatsapp.provider_config` (existing jsonb) | Chatwoot | `{ "connection_state", "connected_at", "last_error" }` — no secrets |
| `wadesk_engine.sessions` | Engine | `id, expected_phone, webhook_url, link_method, state, me_jid, me_lid, updated_at` |
| `wadesk_engine.auth_keys` | Engine | `session_id, key, value_encrypted` (Baileys creds + signal keys) |
| `wadesk_engine.messages` | Engine | `session_id, message_id, payload (encrypted: key + media part incl. media key), created_at` — media messages only, 30-day retention |
| `wadesk_engine.outbox` | Engine | `id, session_id, webhook_url, payload, attempts, next_attempt_at` (URL stored per event so final events survive session deletion) |
| `wadesk_consent_events` (new table) | Chatwoot | `account_id, contact_id, kind (opt_in/opt_out), scope, source, evidence, recorded_by, created_at` — append-only (ADR-0006) |

## 6. Security

- Engine listens only on the internal network; no host port in production.
- Two independent secrets: `WADESK_ENGINE_API_TOKEN` (Chatwoot→engine) and `WADESK_ENGINE_WEBHOOK_SECRET`
  (engine→Chatwoot HMAC). `WADESK_ENGINE_ENCRYPTION_KEY` encrypts credentials at rest.
- Chatwoot's `SafeFetch` private-network guard stays **on**; the engine client uses a direct HTTP client to a
  configured internal URL instead of going through user-supplied webhook plumbing.
- Logs redact message content, phone numbers are truncated in logs, tokens never logged.

## 7. Scalability path

Step 1 runs one engine instance (target ≥50 sessions, WW-NFR-04). Sessions are keyed by `sessionId` and hold
no in-process state that cannot be rebuilt from Postgres, so a later step can shard sessions across instances
(assignment column + router) without changing the Chatwoot contract.

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| WhatsApp restricts numbers (unwanted/bulk messaging, user reports, unofficial clients) | Client loses number, blames WaDesk | Safety layer (ADR-0006): Web is conversations-only, new-chat cap and rate limits, opt-out capture, clear disclosure (WW-NFR-10); never promise ban-proof |
| Baileys breaks after a WhatsApp protocol change; v7 is a release candidate | Channel down for all Web customers | Exact pinning, adapter layer around Baileys, fast-upgrade runbook, monitoring of disconnect spikes |
| LID migration changes contact identity | Duplicate contacts | Store LID as alternate identifier, link when phone known; contract tests with LID fixtures |
| Upstream Chatwoot changes conflict with our edits | Slower upgrades | Touch-point list, additive files, `upstream-sync` PRs with full test run |
| Memory per session higher than expected | Server cost | Measure in M6, set per-instance session cap, shard later |
