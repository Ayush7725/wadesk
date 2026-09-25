# ADR-0006: WhatsApp Safety Layer

- **Status:** Accepted (Change request CR-001, approved 2026-09-25) · **Date:** 2026-09-25

## Context
WhatsApp restricts or bans numbers based on behaviour signals it does not publish in detail: users blocking and
reporting a business, unsolicited messages, bulk/automated messaging, overuse of broadcasts, and use of unofficial
clients (WhatsApp's Business Messaging Policy and Help Center say this directly). Businesses also report restrictions
they believe were mistaken, so no vendor can promise a number will never be restricted.

WaDesk sells to businesses. If a client's number is restricted, the client will look at WaDesk first. The product
therefore has to prevent *avoidable* risk, make risky behaviour visible before it happens, and keep an audit trail.

Relevant facts about our base:
- Chatwoot's WhatsApp campaigns already require the Official (`whatsapp_cloud`) provider and approved templates.
- For Official numbers Meta exposes a real **quality rating** and **messaging limit tier**, already read by
  `Whatsapp::HealthService`.
- Chatwoot's **audit logs** and **custom roles** are Enterprise-only (`enterprise/config/premium_features.yml`), which
  we do not use (ADR-0001). CE has only Administrator and Agent roles.

## Decision
1. **Safety is a core product layer**, owned by WaDesk, not delegated to Chatwoot or the engine.
2. **WhatsApp Web connections are conversations-only.** No campaigns, broadcasts or bulk sends through `baileys`
   inboxes, enforced server-side. Business-initiated chats on Web are capped per number per day. Bulk and marketing
   messaging is only available on the Official API.
3. **Limits exist to prevent spam, not to disguise automation.** WaDesk never implements features whose purpose is to
   evade WhatsApp's detection (fake typing, randomised "human" delays, fingerprint masking). Rate limits are plain
   throughput and volume caps.
4. **Consent is recorded as an append-only event history** (opt-in / opt-out, scope, source, evidence, who recorded
   it). Current consent state is derived from it. Opting out of marketing never blocks replies to a customer's own
   messages.
5. **No invented risk scores.** Dashboards show observable metrics (delivery, read, opt-outs, failures, volume versus
   history) and, for Official numbers, Meta's own quality rating and limit tier. WaDesk never shows a "ban probability".
6. **The unofficial nature of WhatsApp Web is disclosed at onboarding** and acknowledged by the admin (WW-NFR-10), and
   is never marketed as ban-proof or equivalent to the Official API.
7. WaDesk builds its own **audit log** and a minimal **campaign permission** instead of relying on Enterprise features.

Detailed requirements and phasing: [04-safety-requirements.md](../04-safety-requirements.md).

## Consequences
- ✅ Removes the highest-risk use of the Web plan (bulk sending over an unofficial client).
- ✅ Clear positioning: "Web = conversations; Official = conversations + campaigns".
- ✅ Consent history and audit trail support clients in disputes and make WaDesk look professional.
- ⚠️ Some prospects want "unlimited bulk WhatsApp"; we decline that market segment on purpose.
- ⚠️ New Chatwoot touch points (campaign audience filtering, consent storage) must be kept small and listed.
- ⚠️ Caps are our own conservative defaults, not Meta thresholds; they must be configurable by the platform operator.

## Alternatives considered
- **Allow limited campaigns on Web** — more sellable, but concentrates ban risk on the unofficial channel. Rejected by
  the product owner on 2026-09-25.
- **Rely on client discipline and Terms of Service only** — cheapest, but clients will still blame the product. Rejected.
- **"Stealth" sending to avoid detection** — rejected on principle (decision 3).
