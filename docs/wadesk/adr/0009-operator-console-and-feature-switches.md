# ADR-0009: Operator console design and per-client feature switches

- **Status:** Accepted (Change request CR-003, approved 2026-09-27) · **Date:** 2026-09-27

## Context
The first operator pages (ADR-0008) used Chatwoot's plain Administrate look: small tables, no status badges, Chatwoot
branding. The product owner wants the operator side to look and feel like the client product. They also want to hide
Chatwoot features a client does not need (Campaigns, Help Center, Reports, …), per client.

Chatwoot already stores per-account feature flags (`config/features.yml`), but an audit of the Community Edition we
run showed that most of them hide nothing: the sidebar only honours a route's `featureFlag` on branded, cloud or
enterprise installs, the router never checks it, and most APIs are not gated. Premium flags only work in the
enterprise edition, which WaDesk does not use.

## Decision
1. **WaDesk Operator Console.** Super Admin opens on a WaDesk-branded console (Overview, Clients, WhatsApp numbers)
   built with the client dashboard's design tokens, light and dark. Chatwoot's own admin pages stay reachable under
   *Advanced* (`/super_admin/chatwoot`). Design approved from a clickable mockup on 2026-09-27.
2. **Per-client feature switches reuse Chatwoot's account feature flags**, limited to an allow-list of about 25
   client-facing, Community-Edition features (channels, conversations, automation, engagement, insights, team). Premium,
   internal and dead flags are not offered.
3. **Switched-off features are decluttered, not locked.** The client dashboard honours the flags in the sidebar and
   menus, and a direct link to a switched-off page shows "not on your plan". The API is not blocked; a feature sold as a
   paid add-on later gets API enforcement in its own change. Data is kept, so switching a feature back on restores it.
4. Existing accounts get the default-on flags switched on before the dashboard starts honouring them, so no client
   loses a menu on upgrade.

## Amendment (CR-004, 2026-09-27)
After the browser test the product owner asked for **one console with one look**: nothing an operator does should
open Chatwoot's old admin panel. The console therefore also covers:
- **Clients** lifecycle: create a client with its first admin, rename, suspend / reactivate with a reason, delete with
  a typed confirmation (reusing Chatwoot's account creation, suspension and deletion);
- **Users**: search users, see their clients and roles, add to / remove from a client, resend the invitation, set a
  password, grant or remove operator (super admin) access;
- **System health** in plain words (app, database, Redis, WhatsApp engine, email, background jobs summary);
- **Settings**: an allow-list of installation settings that are safe to change.
Developer tools (Sidekiq, platform apps, agent bots, push diagnostics, raw installation configs) and Chatwoot's
dashboard are no longer linked from the console; they stay reachable by URL for developers.

## Consequences
- The operator shapes each client's app without the Rails console.
- API-level locking is a known gap, acceptable for decluttering; required before selling features separately.
- Small upstream edits in the dashboard's policy/router code; listed in
  [02-architecture.md § Upstream touch points](../02-architecture.md#upstream-touch-points).
