# ADR-0004: Store WhatsApp session credentials in Postgres

- **Status:** Accepted · **Date:** 2026-09-25

## Context
A Baileys session consists of long-lived credentials plus many rotating Signal protocol keys. Losing them forces
the customer to re-scan the QR code. Baileys' file-based store is documented as not suitable for production.

## Decision
Implement Baileys' `AuthenticationState` on Postgres in a dedicated schema `wadesk_engine` (same database server as
Chatwoot, separate schema and migrations). Values are encrypted with AES-256-GCM using `WADESK_ENGINE_ENCRYPTION_KEY`.
Signal keys are cached in memory (`makeCacheableSignalKeyStore`) and written through.

## Consequences
- ✅ Sessions survive restarts and container replacement (WW-NFR-01) and are covered by existing DB backups.
- ✅ No extra datastore to operate.
- ⚠️ Rotating the encryption key requires a re-encryption migration (runbook to be written before production).
- ⚠️ Write volume on key updates; measured in M6.

## Alternatives considered
- **Files on a volume** — simplest, but not production-safe and hard to back up/shard.
- **Redis** — fast, but Chatwoot's Redis is treated as a cache/queue and may be evicted.
