# 03 — Delivery plan: Step 1 "WhatsApp Web channel"

**Status:** Approved (Gate A, 2026-09-25) · **Last updated:** 2026-09-25

Each milestone ends with **Gate B**: a demo to the product owner against its acceptance criteria.
Tasks are delivered as one branch + one PR each, following the Definition of Done in [README](README.md).

## Milestones

### M0 — Foundations
Goal: a working, repeatable engineering setup before any feature code.

| Task | Output |
|---|---|
| M0.1 Private GitHub repo, `main` protected, `upstream` remote, PR template | Repo + branch rules |
| M0.2 Trim CI to what we need: keep FOSS RSpec + frontend + lint; disable Chatwoot-org-only workflows (docker publishing, Linear sync, codespaces, nightly installer) | Green CI on `main` |
| M0.3 Containerised dev environment (Ruby 3.4.4, Node 24, pnpm) so specs and dev server run without installing Ruby on the laptop | `make`-style commands documented in README |
| M0.4 `wadesk-engine/` skeleton: TypeScript, Fastify, lint, Vitest, Dockerfile, `/health`; CI job for it | Engine builds and tests in CI |

**Acceptance:** a trivial PR runs CI (Chatwoot specs + engine tests) and merges; `docker compose up` starts Chatwoot + engine locally.

### M1 — Engine: session lifecycle
Covers WW-FR-02, 03, 04, 05, 06, 07, 08 · WW-NFR-01, 02, 05, 06, 07

| Task | Output |
|---|---|
| M1.1 Postgres schema + migrations (`sessions`, `auth_keys`, `messages`, `outbox`) | Migrations |
| M1.2 Encrypted Postgres `AuthStore` for Baileys | Unit tests incl. encrypt/decrypt round-trip, key rotation guard |
| M1.3 `Session` + `SessionManager`: connect, QR, pairing code, expected-number check, reconnect backoff, logout, boot restore | Unit tests with mocked Baileys adapter |
| M1.4 REST API (`PUT/GET/DELETE /sessions/:id`, `pairing-code`) with bearer auth and schema validation | API tests |
| M1.5 Outbox + dispatcher with HMAC signing and retry/backoff; `connection` events | Tests for retry, ordering per session, restart recovery |

**Acceptance:** with curl only, a real test number links via QR and via pairing code; wrong number is rejected;
engine restart restores the session without a new QR; unlinking from the phone produces a `logged_out` webhook.

### M2 — Incoming messages into Chatwoot
Covers WW-FR-01 (backend), 10, 11, 12, 13, 14, 15, 17, 30 (backend)

| Task | Output |
|---|---|
| M2.1 `whatsapp_web` feature flag; `baileys` provider in `Channel::Whatsapp` + lifecycle hooks; API-boundary gating | Model/controller specs |
| M2.2 `Webhooks::WhatsappWebController` (HMAC verify, replay window) + route | Controller specs |
| M2.3 Engine `Normalizer` for text, media, location, contacts, reply context, LID mapping; group/status filtering | Unit tests from recorded fixtures |
| M2.4 `IncomingMessageBaileysService` + job dispatch; media via engine `GET /media` | Service specs using shared contract fixtures |
| M2.5 Contract fixtures shared by both test suites (`wadesk-engine/contract/fixtures/*.json`) | Same JSON verified on both sides |
| M2.6 Regression: prove cloud-only paths (templates sync, health, campaigns, CSAT templates, calling) skip `baileys` | Specs |

**Acceptance:** customer messages (text, image, voice note, document, reply) sent to the test number appear once,
under the right contact, in a WhatsApp inbox; group messages do not appear; all existing WhatsApp specs pass.

### M3 — Outgoing messages and status
Covers WW-FR-20, 21, 22, 23, 24, 25

| Task | Output |
|---|---|
| M3.1 Engine `POST /sessions/:id/messages` (text, one file, quoted reply) with per-session rate limit (SAFE-FR-03) | API tests |
| M3.2 `WhatsappBaileysService#send_message` + error mapping to `external_error` | Provider specs (WebMock) |
| M3.3 Receipts → `statuses` webhook → `Messages::StatusUpdateService` | Normalizer + service specs |
| M3.4 Remove 24h window for `baileys`; new-conversation-by-phone works | Specs |
| M3.5 Daily business-initiated chat cap for Web inboxes (SAFE-FR-02) | Service + request specs |
| M3.6 Block campaigns/bulk on `baileys` inboxes at the API boundary (SAFE-FR-01) | Request specs |
| M3.7 Opt-out keyword detection, consent events table, private note (SAFE-FR-10/11) | Model/service specs incl. Hindi/Hinglish and no-partial-match cases |

**Acceptance:** agent replies (text, image, PDF, quoted reply) arrive on the customer phone; ticks progress
sent → delivered → read; sending while disconnected shows a clear failure; replying after 24h works.

### M4 — Admin UI
Covers WW-FR-01, 02, 03, 05, 06, 08 (UI), 30 (UI), WW-NFR-10

| Task | Output |
|---|---|
| M4.1 "WhatsApp Web" option in the provider picker (flag-gated) with ban-risk acknowledgement | Vue component + vitest |
| M4.2 Creation form + live QR / pairing-code panel with state updates | Vue components + vitest |
| M4.3 Inbox settings: connection panel (state, reconnect, log out) | Vue components + vitest |
| M4.4 In-app notification to admins on `logged_out` / `disconnected` | Spec |
| M4.5 Connection-type badge (Official / Web) on inbox list, settings and conversation header (SAFE-FR-04) | Vue components + vitest |

**Acceptance:** an admin with the flag connects a number end-to-end in the browser without curl; an account without
the flag cannot see or create the channel (UI and API).

### M5 — Hardening and release v0.1
Covers WW-NFR-02, 03, 04, 06, 09, WW-FR-16, 31 and Step 1 release criteria

| Task | Output |
|---|---|
| M5.1 Metrics (`/metrics`), structured logs with redaction audit | Dashboard-ready metrics |
| M5.2 Load test: N simulated sessions → measured memory/CPU per session; set per-instance cap | Report in `docs/wadesk/` |
| M5.3 Fault injection: kill engine / Chatwoot / DB mid-traffic; verify no loss, no duplicates | Test report |
| M5.4 Own-phone echo messages (WW-FR-16) and Super Admin session list (WW-FR-31) if not already done | Specs |
| M5.5 72-hour soak test with 2 real numbers | Test report |
| M5.6 Retire Evolution API from the demo stack; tag `v0.1.0`; release notes | Release |

**Acceptance:** the Step 1 release criteria in [01-requirements.md § 7](01-requirements.md#7-acceptance-for-step-1-release-criteria).

## Test strategy

| Level | Engine (Node) | Chatwoot (Rails/Vue) |
|---|---|---|
| Unit | Vitest; Baileys behind an adapter interface, mocked | RSpec models/services; Vitest components |
| Contract | Shared JSON fixtures of webhook payloads and API responses, validated by both suites | Same fixtures |
| Integration | Engine + real Postgres in CI (service container) | Request/controller specs with WebMock for the engine |
| End-to-end | Manual scripted checklist per milestone with dedicated test numbers (never the business's main number) | |
| Non-functional | Load, fault-injection and soak tests in M5 | |

Test numbers: at least two spare SIMs/numbers reserved for development and soak testing.

## Environments

| Env | Purpose |
|---|---|
| Local (laptop, rootless Podman) | Development and demos |
| CI (GitHub Actions) | Every PR: lint + unit + contract + integration tests |
| Staging (VPS, later) | Soak tests and customer demos before Step 2 go-live |

## Out of this plan (next steps)
Step 2: plans, Razorpay billing, signup and account provisioning, suspension, rebranding; safety S2 (consent history,
opt-in capture, campaign audience filtering and review, campaign permission, audit log — [04-safety-requirements.md](04-safety-requirements.md)).
Step 2 also re-plans with Step 3 items below; the bulk number checker is dropped (looks like contact harvesting).
Step 3+: groups, Status, profile, call auto-reject, history import, AI transcription; safety S3 (WhatsApp Health view with
Meta quality rating, safety events).
