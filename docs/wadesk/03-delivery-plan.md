# 03 — Delivery plan: Step 1 "WhatsApp Web channel"

**Status:** Approved (Gate A, 2026-09-25) · **Last updated:** 2026-09-27

Each milestone ends with **Gate B**: a demo to the product owner against its acceptance criteria.
Tasks are delivered as one branch + one PR each, following the Definition of Done in [README](README.md).

## Milestones

### M0 — Foundations ✅
Goal: a working, repeatable engineering setup before any feature code.

**Status:** complete 2026-09-25 — M0.1/M0.2 on `main`, M0.3 (#2), M0.4 (#1), engine in dev stack (#3).

| Task | Output |
|---|---|
| M0.1 Private GitHub repo, `main` protected, `upstream` remote, PR template | Repo + branch rules |
| M0.2 Trim CI to what we need: keep FOSS RSpec + frontend + lint; disable Chatwoot-org-only workflows (docker publishing, Linear sync, codespaces, nightly installer) | Green CI on `main` |
| M0.3 Containerised dev environment (Ruby 3.4.4, Node 24, pnpm) so specs and dev server run without installing Ruby on the laptop | `make`-style commands documented in README |
| M0.4 `wadesk-engine/` skeleton: TypeScript, Fastify, lint, Vitest, Dockerfile, `/health`; CI job for it | Engine builds and tests in CI |

**Acceptance:** a trivial PR runs CI (Chatwoot specs + engine tests) and merges; `docker compose up` starts Chatwoot + engine locally.

### M1 — Engine: session lifecycle ✅

**Status:** accepted 2026-09-25 ([record](acceptance/M1.md)); the deferred wrong-number check passed on real phones on 2026-09-27 ([record](acceptance/M2-M4.md)).
Covers WW-FR-02, 03, 04, 05, 06, 07, 08 · WW-NFR-01, 02, 05, 06, 07

| Task | Output |
|---|---|
| M1.1 Postgres schema + migrations (`sessions`, `auth_keys`, `messages`, `outbox`) | Migrations |
| M1.2 Encrypted Postgres `AuthStore` for Baileys | Unit tests incl. encrypt/decrypt round-trip, key rotation guard |
| M1.3 `Session` + `SessionManager`: connect, QR, pairing code, expected-number check, reconnect backoff, logout, boot restore | Unit tests with mocked Baileys adapter |
| M1.4 REST API (`PUT/GET/DELETE /sessions/:id`, `pairing-code`) with bearer auth and schema validation | API tests |
| M1.5 Outbox + dispatcher with HMAC signing and retry/backoff; `connection` events | Tests for retry, ordering per session, restart recovery |
| M1.6 Pairing-code mode from acceptance findings: `link_method`, fresh code per connection, expired attempts retried, device label per ADR-0007 | Lifecycle + API tests; verified on a real phone |

**Acceptance:** with curl only, a real test number links via QR and via pairing code; wrong number is rejected;
engine restart restores the session without a new QR; unlinking from the phone produces a `logged_out` webhook.

### M2 — Incoming messages into Chatwoot ✅

**Status:** built (PRs #12–#16); accepted 2026-09-27 after real-phone tests ([record](acceptance/M2-M4.md)).
Covers WW-FR-01 (backend), 10, 11, 12, 13, 14, 15, 17, 30 (backend)

| Task | Output |
|---|---|
| M2.1 `whatsapp_web` feature flag; `baileys` provider in `Channel::Whatsapp` + lifecycle hooks; API-boundary gating | Model/controller specs |
| M2.2 `Webhooks::WhatsappWebController` (HMAC verify, replay window) + route | Controller specs |
| M2.3 Engine `Normalizer` for text, media, location, contacts, reply context, LID mapping; group/status filtering | Unit tests from recorded fixtures |
| M2.4 `IncomingMessageBaileysService` + job dispatch; media via engine `GET /media` | Service specs using shared contract fixtures |
| M2.5 Contract fixtures shared by both test suites (`wadesk-engine/contract/fixtures/*.json`) | Same JSON verified on both sides |
| M2.6 Regression: prove cloud-only paths (templates sync, health, campaigns, CSAT templates, calling) skip `baileys` | Specs — found campaigns accepted Web inboxes; M3.6 guard pulled forward into M2.6 |

**Acceptance:** customer messages (text, image, voice note, document, reply) sent to the test number appear once,
under the right contact, in a WhatsApp inbox; group messages do not appear; all existing WhatsApp specs pass.

### M3 — Outgoing messages and status ✅

**Status:** built (PRs #17–#23, incl. safety items M3.5–M3.7 and a security fix keeping Signal keys out of logs); accepted 2026-09-27 after real-phone tests ([record](acceptance/M2-M4.md)).
Covers WW-FR-20, 21, 22, 23, 24, 25

| Task | Output |
|---|---|
| M3.1 Engine `POST /sessions/:id/messages` (text, one file, quoted reply) with per-session rate limit (SAFE-FR-03) | API tests |
| M3.2 `WhatsappBaileysService#send_message` + error mapping to `external_error` | Provider specs (WebMock) |
| M3.3 Receipts → `statuses` webhook → `Messages::StatusUpdateService` | Normalizer + service specs |
| M3.4 Remove 24h window for `baileys`; new-conversation-by-phone works | Specs |
| M3.5 Daily business-initiated chat cap for Web inboxes (SAFE-FR-02) | Service + request specs |
| M3.6 Block campaigns/bulk on `baileys` inboxes at the API boundary (SAFE-FR-01) | ✅ Done in M2.6 (model guard, 422 on create) |
| M3.7 Opt-out keyword detection, consent events table, activity note for agents (SAFE-FR-10/11) | Model/service/listener specs incl. Hindi/Hinglish and no-partial-match cases |

**Acceptance:** agent replies (text, image, PDF, quoted reply) arrive on the customer phone; ticks progress
sent → delivered → read; sending while disconnected shows a clear failure; replying after 24h works.

### M4 — Admin UI ✅

**Status:** built (PRs #24, #25); tested in the browser with the GitHub-built bundle on 2026-09-27, fixes #30–#35; accepted 2026-09-27 ([record](acceptance/M2-M4.md)).
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
| M5.2 Load test: measured memory/CPU per session; set per-instance cap. Done with real linked numbers on the staging server (simulating many WhatsApp connections from one IP risks it being flagged as abuse) | Report in `docs/wadesk/` |
| M5.3 Fault injection: kill engine / Chatwoot / DB mid-traffic; verify no loss, no duplicates | Test report |
| M5.4 Own-phone echo messages (WW-FR-16) — done (#28). Super Admin session list (WW-FR-31) moved to the Step 2 operator screen (see Open items) | Specs |
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

## Open items

| Item | Found | Needed by |
|---|---|---|
| **Operator screen for per-account settings** — now planned as S2.1 below (CR-002). | M3.5 | Step 2 (before the first paying client) |
| **Run production without Chatwoot's enterprise code** (`DISABLE_ENTERPRISE=true` or no `enterprise/` in the image), as ADR-0001 assumes. Today `enterprise/` ships in the image; without a Chatwoot licence its daily `ReconcilePlanConfigService` resets all brand settings (name, logos, links) to Chatwoot's and switches premium features off. Until then the console shows branding read-only. Check what else the switch changes before go-live. | S2.3 (#55) | Staging setup, before the first paying client |

## S2.1 — Operator screen and plan lock (CR-002, ADR-0008)

**Status:** in progress. Covers WW-FR-31, 32, 33 · SAFE-FR-02 (operator setting), SAFE-NFR-03

| Task | Output |
|---|---|
| S2.1a *WhatsApp Web numbers* page in Super Admin: every Web number, state, reason, last change, needs-re-link marker; attention first | Request specs incl. access control and nav entry |
| S2.1b `whatsapp_official` flag (on for new and existing accounts); create-only gates for Official and Web channels at the model; Official options hidden in the new-inbox UI without the flag | Model, API (422) and frontend specs; existing inboxes keep saving after a flag is turned off |
| S2.1c *WaDesk clients* page in Super Admin: switch Official / Web per account, set the daily new-chat limit | Request specs incl. invalid limits and the flag state the dashboard reads |

**Acceptance:** without the console, the operator switches a test account to Web-only (the Official options disappear
for it, its existing inboxes keep working), sets its daily new-chat limit, and sees its WhatsApp Web number and state
on the numbers page. *Met in the browser test on 2026-09-27 (PRs #41–#45).*

## S2.2 — Operator console and feature switches (CR-003, ADR-0009)

**Status:** in progress. Covers WW-FR-34 and the approved console design

| Task | Output |
|---|---|
| S2.2a Console shell: WaDesk-branded layout and sidebar, light/dark, Chatwoot admin under *Advanced* | Request specs (entry point, access, attention count) |
| S2.2b Overview and WhatsApp numbers pages redesigned in the console | Request specs with realistic data, N+1 checks |
| S2.2c Clients list and client page redesigned; *Features* section with the allow-listed switches | Request specs incl. allow-list, invalid input, what the dashboard reads |
| S2.2d Client dashboard honours feature flags: hidden in sidebar/menus, "not on your plan" for direct links; default-on flags enabled for existing accounts | Vitest on real sidebar/router logic; migration spec |

**Acceptance:** in the browser, the operator turns off Campaigns and Reports for a test client from its page in the
console; that client's app no longer shows them and their links say "not on your plan"; turning them back on restores
them. The console matches the approved mockup in light and dark mode and on a phone-width window.

## S2.3 — One operator console (CR-004, ADR-0009 amendment)

**Status:** in progress. Covers WW-FR-35

| Task | Output |
|---|---|
| S2.3a Console navigation: Users, System health, Settings; Chatwoot admin and developer tools unlinked | Request specs (nav, access) |
| S2.3b Clients lifecycle: new client with first admin, rename, suspend / reactivate, delete | Request specs per flow, incl. invitation email and typed delete confirmation |
| S2.3c Users: search, memberships, invitation, password, operator access with guards | Request specs incl. last-admin / last-operator / self guards |
| S2.3d System health (plain words, no secrets) and Settings (allow-listed, validated) | Request specs incl. engine down, job counts, settings reaching where they are used |

**Acceptance:** in the browser, the operator creates a test client with its admin, suspends and reactivates it, adds a
user to it, checks System health and changes an allowed setting, all without leaving the console's design.

## Out of this plan (next steps)
Step 2: plans, Razorpay billing, signup and account provisioning, suspension, rebranding; safety S2 (consent history,
opt-in capture, campaign audience filtering and review, campaign permission, audit log — [04-safety-requirements.md](04-safety-requirements.md)).
Step 2 also re-plans with Step 3 items below; the bulk number checker is dropped (looks like contact harvesting).
Step 3+: groups, Status, profile, call auto-reject, history import, AI transcription; safety S3 (WhatsApp Health view with
Meta quality rating, safety events).
