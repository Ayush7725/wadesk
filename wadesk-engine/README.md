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
| `WADESK_ENGINE_DATABASE_URL` | — (required) | Postgres URL. The engine uses its own schema `wadesk_engine` and applies its migrations (`migrations/*.sql`) at startup under an advisory lock |

## Version notes

- **TypeScript is pinned to 6.0.x** because `typescript-eslint` 8.x does not yet support TypeScript 7 (peer range `<6.1`).
  Upgrade both together.
- Dependencies are pinned to exact versions; upgrades go through dedicated PRs (Baileys especially — see ADR-0002).
