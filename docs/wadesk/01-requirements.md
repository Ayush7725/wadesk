# 01 — Requirements: Step 1 "WhatsApp Web channel"

**Status:** Approved (Gate A, 2026-09-25) · **Owner:** Product (founder) · **Last updated:** 2026-09-25

## 1. Context and goal

WaDesk sells three plans to businesses: **Official** (WhatsApp Cloud API), **Web** (WhatsApp Web / QR-linked
device), and **Both**. Chatwoot already provides the Official channel and the shared inbox. Today the Web channel
is provided by a separate product (Evolution API). **Step 1 makes WhatsApp Web a native channel of WaDesk**,
so the product runs from one codebase and Evolution API can be retired.

**Success = a business connects its number by scanning a QR code inside WaDesk, and its agents can receive and
reply to text, media and replies from the shared inbox, with delivery/read ticks — without Evolution API.**

## 2. Scope

**In scope (Step 1):** connecting/disconnecting a number, 1:1 chats, text, media, reply-to, delivery status,
per-account enablement, reliability across restarts.

**Out of scope (later steps):** groups, Status posting, polls/reactions/stickers sending, number checker, profile
editing, call auto-reject, history import, voice-note transcription, billing/plans UI, rebranding. The design
must not block these.

## 3. Actors

| Actor | Description |
|---|---|
| Account admin | Business owner/manager who connects the WhatsApp number. |
| Agent | Staff member replying to customers from the inbox. |
| Customer | The business's end customer, messaging from normal WhatsApp. |
| Platform operator | WaDesk (us): runs the servers, enables features per account. |

## 4. Functional requirements

Priority: **M** = must for Step 1, **S** = should (in Step 1 if time allows), **C** = could (later).

### 4.1 Connection lifecycle

| ID | Requirement | Pri |
|---|---|---|
| WW-FR-01 | An account admin can create a "WhatsApp Web" inbox by entering an inbox name and the WhatsApp phone number (E.164). | M |
| WW-FR-02 | After creation, WaDesk shows a QR code that refreshes automatically until scanned or the admin cancels. | M |
| WW-FR-03 | As an alternative to QR, the admin can request an 8-character **pairing code** to enter on the phone. | S |
| WW-FR-04 | If the scanned phone's number differs from the number entered in WW-FR-01, the link is rejected and the admin sees a clear error. | M |
| WW-FR-05 | The inbox shows its connection state: `connecting`, `qr_pending`, `connected`, `disconnected`, `logged_out`. | M |
| WW-FR-06 | The admin can reconnect a disconnected inbox (new QR) and disconnect (log out) a connected one. | M |
| WW-FR-07 | Deleting the inbox logs the device out of WhatsApp and deletes its stored session credentials. | M |
| WW-FR-08 | If the user unlinks WaDesk from the phone, the inbox moves to `logged_out` and admins are notified in-app. | M |

### 4.2 Incoming messages (customer → business)

| ID | Requirement | Pri |
|---|---|---|
| WW-FR-10 | Incoming 1:1 text messages appear in the inbox under the correct contact and conversation, using the same conversation rules as the Official channel. | M |
| WW-FR-11 | Incoming images, video, audio/voice notes, documents and stickers appear as attachments (with captions). | M |
| WW-FR-12 | Incoming location and contact-card messages are displayed (as in the Official channel). | S |
| WW-FR-13 | When a customer replies to a specific message, the conversation shows the quoted message. | M |
| WW-FR-14 | Contacts are identified by phone number; the customer's WhatsApp profile name is stored on the contact. When WhatsApp only exposes a privacy ID (LID), it is stored as an alternate identifier and linked to the phone number when available. | M |
| WW-FR-15 | Group messages, broadcast lists, Status updates and newsletters are ignored in Step 1 (not shown, not errors). | M |
| WW-FR-16 | Messages sent from the business's own phone (not via WaDesk) appear in the conversation as outgoing messages. | S |
| WW-FR-17 | Each WhatsApp message is shown exactly once, even after reconnects, restarts or duplicate deliveries. | M |

### 4.3 Outgoing messages (business → customer)

| ID | Requirement | Pri |
|---|---|---|
| WW-FR-20 | An agent's text reply is delivered to the customer on WhatsApp. | M |
| WW-FR-21 | An agent can send one attachment (image, video, audio, document) with an optional caption. | M |
| WW-FR-22 | An agent can reply to a specific customer message (quoted reply). | M |
| WW-FR-23 | Outgoing messages show status ticks: sent → delivered → read, or failed with a readable reason. | M |
| WW-FR-24 | The Official channel's 24-hour reply window and template requirement do **not** apply to WhatsApp Web inboxes. | M |
| WW-FR-25 | An agent can start a new conversation with a contact by phone number from WaDesk. | S |

### 4.4 Administration

| ID | Requirement | Pri |
|---|---|---|
| WW-FR-30 | The WhatsApp Web channel type is only offered to accounts where the platform operator has enabled the `whatsapp_web` feature (plan gating). | M |
| WW-FR-31 | The platform operator can see all WhatsApp Web sessions and their states in Super Admin. | S |

## 5. Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| WW-NFR-01 | Reliability | Sessions survive a restart of any component without re-scanning the QR code. |
| WW-NFR-02 | Reliability | After a network drop or engine restart, a session reconnects automatically within 60 s; messages received meanwhile are delivered once reconnected (WhatsApp offline sync). |
| WW-NFR-03 | Latency | An incoming message appears in the inbox within 3 s (p95) of WhatsApp delivering it to the linked device; an outgoing reply is handed to WhatsApp within 3 s (p95). |
| WW-NFR-04 | Capacity | One engine instance supports at least **50 connected numbers**; the design allows adding instances later. Actual per-session memory is measured in M6 and recorded. |
| WW-NFR-05 | Security | The engine is never exposed to the internet; all Chatwoot↔engine calls are authenticated with a shared secret. Session credentials are stored encrypted at rest. |
| WW-NFR-06 | Isolation | A failure in one session (bad credentials, ban, crash) does not affect other sessions. |
| WW-NFR-07 | Privacy | Message content and credentials are never written to logs. |
| WW-NFR-08 | Maintainability | Upstream Chatwoot changes are limited to the touch points listed in the architecture doc; everything else is new files. |
| WW-NFR-09 | Operability | Engine exposes health and basic metrics (sessions by state, messages in/out, errors). |
| WW-NFR-10 | Compliance | The inbox creation screen tells the admin that WhatsApp Web is unofficial and may lead to number bans if used for bulk messaging; the admin must acknowledge before connecting. |

## 6. Constraints and assumptions

- WhatsApp Web access is via the open-source **Baileys** library (MIT). It is unofficial and may break when
  WhatsApp changes its protocol; we pin versions and upgrade deliberately.
- One WhatsApp number can link up to 4 companion devices; WaDesk occupies one.
- The business's phone must come online at least once every 14 days or WhatsApp unlinks companion devices.
- Chatwoot's `enterprise/` directory is not used or modified.

## 7. Acceptance for Step 1 (release criteria)

1. All **M** requirements pass their acceptance tests (see delivery plan).
2. The existing Official WhatsApp channel specs still pass unchanged.
3. A 72-hour soak test with at least 2 real test numbers shows no lost or duplicated messages and automatic recovery
   from forced engine restarts.
4. The demo environment runs with Evolution API removed.
