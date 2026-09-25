# wadesk-engine

Internal WhatsApp Web engine for WaDesk. It wraps [Baileys](https://github.com/WhiskeySockets/Baileys) and exposes
a small REST + webhook contract to Chatwoot. It has no UI and must never be exposed to the internet.

Design: [docs/wadesk/02-architecture.md](../docs/wadesk/02-architecture.md) · Decision: [ADR-0002](../docs/wadesk/adr/0002-whatsapp-web-engine-sidecar.md)

## Commands

| Command | Purpose |
|---|---|
| `pnpm install` | Install dependencies (own lockfile; not part of Chatwoot's pnpm project) |
| `pnpm dev` | Run with reload on `WADESK_ENGINE_PORT` (default 4000) |
| `pnpm test` | Tests (Vitest) against a real Postgres; creates the test DB on first run. Locally: `bin/wadesk-dev engine test` |
| `pnpm lint` / `pnpm typecheck` | ESLint (typescript-eslint strict) / `tsc --noEmit` |
| `pnpm build` && `pnpm start` | Production build and start |

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `WADESK_ENGINE_PORT` | `4000` | HTTP port |
| `WADESK_ENGINE_HOST` | `0.0.0.0` | Bind address (container network only) |
| `WADESK_ENGINE_LOG_LEVEL` | `info` | pino log level |
| `WADESK_ENGINE_API_TOKEN` | — (required) | Bearer token Chatwoot uses for the session API; at least 32 characters |
| `WADESK_ENGINE_ENCRYPTION_KEY` | — (required) | Base64 of 32 random bytes (`openssl rand -base64 32`); encrypts stored WhatsApp credentials. Changing it makes existing sessions unreadable (ADR-0004) |
| `WADESK_ENGINE_WEBHOOK_SECRET` | — (required) | Shared secret for signing webhooks to Chatwoot; at least 32 characters |
| `WADESK_ENGINE_DATABASE_URL` | — (required) | Postgres URL. The engine uses its own schema `wadesk_engine` and applies its migrations (`migrations/*.sql`) at startup under an advisory lock |

## API

All routes except `/health` need `Authorization: Bearer $WADESK_ENGINE_API_TOKEN`. Errors are `{"error": {"code", "message"}}`.

| Route | Result |
|---|---|
| `PUT /sessions/:id` `{phone_number, webhook_url, link_method?}` | `202 {state}` — create or restart; idempotent while live. `link_method`: `qr` (default) or `code` |
| `GET /sessions/:id` | `{state, qr?, pairing_code?, me?, last_error?}` — in `code` mode `pairing_code` is always the currently valid code |
| `DELETE /sessions/:id` | `204` — logs out and wipes credentials |
| `GET /health` | `{status: "ok"}` or `503` when the database is down |

## Events to Chatwoot (outbox)

Every event for Chatwoot is written to `wadesk_engine.outbox` first, then POSTed to the session's webhook URL with
`X-WaDesk-Timestamp` and `X-WaDesk-Signature: sha256=HMAC(secret, "<timestamp>.<body>")`, and deleted on a 2xx.

- **Order:** only the oldest pending event of a session is sent, so one number's events never arrive out of order.
- **Retries:** exponential backoff (2 s, 4 s, … up to 10 min). Events still failing after 48 h are dropped and logged.
- **Restarts / multiple instances:** undelivered events survive restarts; claims use a 60 s lease with
  `FOR UPDATE SKIP LOCKED`, so parallel dispatchers never send the same event concurrently.

## Version notes

- **TypeScript is pinned to 6.0.x** because `typescript-eslint` 8.x does not yet support TypeScript 7 (peer range `<6.1`).
  Upgrade both together.
- Dependencies are pinned to exact versions; upgrades go through dedicated PRs (Baileys especially — see ADR-0002).
- pnpm skips dependency install scripts by default. For `baileys` (checks Node ≥ 20) and `protobufjs` (prints a
  dependency-version warning) this is intended: neither builds or downloads anything.
