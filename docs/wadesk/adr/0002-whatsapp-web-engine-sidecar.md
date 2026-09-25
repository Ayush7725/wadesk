# ADR-0002: WhatsApp Web runs in an internal Node sidecar built on Baileys

- **Status:** Accepted · **Date:** 2026-09-25

## Context
WhatsApp Web access requires implementing WhatsApp's multi-device protocol. The only mature, maintained
open-source implementation is **Baileys** (TypeScript, MIT). There is no production-grade Ruby equivalent,
and reimplementing the protocol in Ruby would be months of work and would break with every protocol change.

## Decision
Create `wadesk-engine/`, a small Node/TypeScript service inside the WaDesk repository that wraps Baileys and
exposes a minimal REST + webhook contract to Chatwoot. It runs as an internal-only service in the same deployment.
We write our own engine instead of copying Evolution API code.

## Consequences
- ✅ One repository, one deployment, one database, one UI — the engine has no UI or login of its own.
- ✅ Baileys upgrades are isolated to one service behind an adapter.
- ✅ No Evolution API licence obligations (its extra notice/logo conditions do not apply).
- ⚠️ Two runtimes (Ruby and Node) in the product; Chatwoot already requires Node for its frontend build.
- ⚠️ We own reconnection, storage and media handling logic (Evolution API is kept as a behavioural reference).

## Alternatives considered
- **Keep Evolution API** — large general-purpose API (≈10–15% of it needed), separate product and licence terms.
- **Embed Baileys inside Rails via a JS runtime** — not viable for long-lived sockets.
