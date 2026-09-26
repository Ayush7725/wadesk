# 04 — Requirements: WhatsApp Safety Layer

**Status:** Approved (CR-001, 2026-09-25) · **Last updated:** 2026-09-25 · Decision: [ADR-0006](adr/0006-whatsapp-safety-layer.md)

## 1. Goal

Reduce avoidable WhatsApp restrictions for WaDesk clients, make risky behaviour visible *before* messages are sent,
and keep an audit trail of who sent what, when and through which connection. WaDesk does **not** promise that a number
can never be restricted.

Product principle: WaDesk encourages *customer → business → conversation → relationship*, not
*database → bulk send → repeat*.

## 2. Concepts

| Term | Meaning |
|---|---|
| **Customer-initiated conversation** | The contact sent the first message on this inbox. |
| **Business-initiated chat** | An outgoing message to a contact who has never sent an inbound message on this inbox. |
| **Consent event** | An append-only record: `opt_in` or `opt_out`, scope (`marketing`), source (message, form, import, agent, API), evidence (e.g. detected text), recorded by, timestamp. |
| **Marketing consent state** | Derived from the latest consent event: `opted_in`, `opted_out` or `unknown`. |
| **Official / Web connection** | `whatsapp_cloud` provider / `baileys` provider. |

Contacting us about an enquiry is **not** marketing consent. An opt-out never blocks replies to the customer's own messages.

## 3. Requirements

Phase: **S1** = Step 1 (current), **S2** = Step 2 (billing + campaigns), **S3** = later. Priority as in 01-requirements.

### 3.1 Connection-level guardrails

| ID | Requirement | Phase | Pri |
|---|---|---|---|
| SAFE-FR-01 | Web (`baileys`) inboxes cannot be used for campaigns, broadcasts or bulk sends. The campaign UI does not offer them and the API rejects them. | S1 | M |
| SAFE-FR-02 | Business-initiated chats on a Web inbox are capped per number per rolling 24 hours (default **20**, operator-configurable per account via `custom_attributes['wadesk_whatsapp_web_daily_new_chats']`). Beyond the cap the send fails with a clear reason; replies to customers who wrote in are never capped. | S1 | M |
| SAFE-FR-03 | Outgoing messages per Web number are rate-limited (default **20/minute**); excess messages are queued, not dropped. | S1 | M |
| SAFE-FR-04 | The inbox list, inbox settings and conversation header show the connection type (Official / Web). Web shows a short "unofficial connection" notice with a link to details. | S1 | M |
| SAFE-FR-05 | WaDesk does not implement features intended to evade WhatsApp's detection (see ADR-0006 decision 3). | S1 | M |

### 3.2 Consent and opt-out

| ID | Requirement | Phase | Pri |
|---|---|---|---|
| SAFE-FR-10 | Incoming messages whose whole normalised text matches an opt-out keyword record a marketing `opt_out` consent event. The default list covers English and common Hindi/Hinglish forms (e.g. `stop`, `unsubscribe`, `opt out`, `band karo`, `mat bhejo`) and is operator-configurable. Partial matches inside longer sentences do not trigger. | S1 | M |
| SAFE-FR-11 | On opt-out, a private note is added to the conversation so agents see it; no automatic reply is sent on Web connections. | S1 | S |
| SAFE-FR-12 | Consent events are append-only and viewable per contact as a history (date, change, source, evidence, recorded by). | S2 | M |
| SAFE-FR-13 | Admins can record opt-in with source and purpose (manual, CSV import with a mandatory source column, API). | S2 | M |
| SAFE-FR-14 | Contacts can opt back in only via a new `opt_in` event with a source; no silent reversal. | S2 | M |

### 3.3 Campaign safety (Official only)

| ID | Requirement | Phase | Pri |
|---|---|---|---|
| SAFE-FR-20 | Campaign audiences are filtered before sending: only `opted_in` contacts with valid numbers are eligible; opted-out, unknown-consent, invalid and previously hard-failed contacts are excluded. | S2 | M |
| SAFE-FR-21 | A campaign review screen shows selected / eligible counts and each exclusion reason, and requires explicit confirmation. | S2 | M |
| SAFE-FR-22 | For any excluded contact, the UI can show *why* it was excluded. | S2 | M |
| SAFE-FR-23 | The review warns when a campaign is much larger than the account's recent campaigns or daily volume (thresholds configurable), showing previous results (delivered, read, replies, opt-outs). It never states a WhatsApp "limit" or "ban probability". | S2 | S |
| SAFE-FR-24 | Only users with the **campaign** permission can create campaigns or import audiences; only administrators can approve and send them. | S2 | M |

### 3.4 Visibility and audit

| ID | Requirement | Phase | Pri |
|---|---|---|---|
| SAFE-FR-30 | An audit log records campaign creation, approval, sending, audience imports, consent changes by users, inbox connect/disconnect and safety-limit hits: actor, action, target, channel, timestamp. | S2 | M |
| SAFE-FR-31 | For every outgoing campaign message, the admin can trace campaign, creator, approver, template and connection. | S2 | M |
| SAFE-FR-32 | A per-number WhatsApp Health view shows connection state, volumes, delivery/read rates, opt-outs and failures; for Official numbers also Meta's quality rating and messaging limit tier. | S3 | S |
| SAFE-FR-33 | Safety events (limit hits, opt-out spikes, failure-rate increases, unusual volume) are recorded and visible to account admins and the platform operator. | S3 | S |

### 3.5 Non-functional

| ID | Requirement |
|---|---|
| SAFE-NFR-01 | Safety checks run at the server boundary (API/service), never only in the UI. |
| SAFE-NFR-02 | Consent and audit records are retained for at least 2 years and are not editable by account users. |
| SAFE-NFR-03 | All caps and thresholds are configuration, with conservative defaults, adjustable by the platform operator only. |
| SAFE-NFR-04 | Onboarding copy, marketing and sales material never describe Web connections as ban-proof or equivalent to the Official API. |

## 4. Out of scope

Engagement scoring, automated risk rules, cross-client monitoring and automated incident detection are considered
after S3, based on real usage data.
