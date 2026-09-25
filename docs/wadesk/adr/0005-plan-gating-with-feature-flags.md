# ADR-0005: Gate channel types per account with Chatwoot feature flags

- **Status:** Accepted · **Date:** 2026-09-25

## Context
Plans are Official, Web, and Both. The product must only let an account create the channel types it pays for.
Chatwoot already has per-account feature flags (`config/features.yml`, `account.feature_enabled?`, and
`isCloudFeatureEnabled` in the frontend).

## Decision
Add a `whatsapp_web` feature flag (appended with `column: feature_flags_ext_1`). The WhatsApp Web provider is offered
and accepted only when it is enabled. The check is enforced at the API boundary (inbox creation) and mirrored in the UI.
Gating for the Official channel and the billing integration that toggles flags are designed in Step 2.

## Consequences
- ✅ Reuses existing, tested mechanisms; Super Admin can toggle it today.
- ✅ Billing (Step 2) only needs to flip flags on plan changes.
- ⚠️ Disabling the flag does not disconnect existing inboxes; suspension behaviour is defined in Step 2.
