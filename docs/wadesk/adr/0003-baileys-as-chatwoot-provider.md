# ADR-0003: Integrate as a `baileys` provider of `Channel::Whatsapp`

- **Status:** Accepted · **Date:** 2026-09-25

## Context
Chatwoot's `Channel::Whatsapp` already supports pluggable providers (`default` = 360dialog, `whatsapp_cloud`),
with a shared incoming pipeline (`IncomingMessageBaseService`: dedup, contact resolution, conversation rules,
attachments, reply-to) and a shared outgoing path (`SendOnWhatsappService`). An alternative is a brand-new
channel type (`Channel::WhatsappWeb`).

## Decision
Add a third provider, `baileys`, to `Channel::Whatsapp`. The engine emits payloads in the Cloud API message/status
shape so the existing incoming pipeline is reused. Provider-specific differences (no 24h window, no templates,
media fetched from the engine) are handled in the new provider/service classes plus a few listed touch points.

## Consequences
- ✅ Reuses the inbox, contact, campaign-exclusion, reporting and automation behaviour of WhatsApp inboxes.
- ✅ Frontend treats it as WhatsApp (icons, filters, reports) with a small provider-specific panel.
- ✅ "Both" plan customers see both kinds of number in one familiar channel type.
- ⚠️ Cloud-only code paths must skip `baileys`; most already check `provider == 'whatsapp_cloud'` — verified by specs.
- ⚠️ The phone number must be known at creation (unique column); we ask for it and verify it on link (WW-FR-04).

## Alternatives considered
- **New `Channel::WhatsappWeb` type** — cleaner separation but duplicates the incoming pipeline and needs many more
  upstream edits (channel lists, reports, filters, icons). Rejected.
- **Use `Channel::Api` (what Evolution does)** — loses WhatsApp-specific behaviour and UI. Rejected.
