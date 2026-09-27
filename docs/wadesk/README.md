# WaDesk — Engineering Handbook

WaDesk (working codename) is a multi-tenant WhatsApp enquiry-management product built as a fork of
[Chatwoot](https://github.com/chatwoot/chatwoot). It supports both the official WhatsApp Cloud API and
WhatsApp Web (QR-linked devices) from one codebase.

## Documents

| Doc | Purpose | Status |
|---|---|---|
| [01-requirements.md](01-requirements.md) | What Step 1 must do (functional + non-functional requirements) | Approved 2026-09-25 |
| [02-architecture.md](02-architecture.md) | How it is built: components, contracts, data flows | Approved 2026-09-25 |
| [03-delivery-plan.md](03-delivery-plan.md) | Milestones, tasks, acceptance criteria, test strategy | Approved 2026-09-25 |
| [04-safety-requirements.md](04-safety-requirements.md) | WhatsApp Safety Layer requirements and phasing | Approved 2026-09-25 (CR-001) |
| [acceptance/](acceptance/) | Milestone acceptance records (Gate B) | M1, M2–M4 |
| [adr/](adr/) | Architecture Decision Records — one file per significant decision | See index below |

### ADR index

| # | Decision | Status |
|---|---|---|
| [0001](adr/0001-fork-chatwoot.md) | Build the product as a fork of Chatwoot | Accepted |
| [0002](adr/0002-whatsapp-web-engine-sidecar.md) | WhatsApp Web runs in an internal Node sidecar built on Baileys | Accepted |
| [0003](adr/0003-baileys-as-chatwoot-provider.md) | Integrate as a `baileys` provider of `Channel::Whatsapp`, reusing the incoming pipeline | Accepted |
| [0004](adr/0004-session-state-in-postgres.md) | Store WhatsApp session credentials in Postgres | Accepted |
| [0005](adr/0005-plan-gating-with-feature-flags.md) | Gate channel types per account with Chatwoot feature flags | Accepted |
| [0006](adr/0006-whatsapp-safety-layer.md) | WhatsApp Safety Layer; Web connections are conversations-only | Accepted (CR-001) |
| [0007](adr/0007-device-label-per-link-method.md) | Device label depends on link method (QR "WaDesk", code "Chrome (Ubuntu)") | Accepted |
| [0008](adr/0008-operator-screen-and-plan-flags.md) | Operator screen in Super Admin; plans as create-only feature flags | Accepted (CR-002) |
| [0009](adr/0009-operator-console-and-feature-switches.md) | Operator console design; per-client feature switches (hide, not lock) | Accepted (CR-003) |

## Development process (SDLC)

We follow a gated, iterative lifecycle. Each gate requires product-owner approval before work continues.

```
 Requirements ──▶ Design ──▶ Plan ──▶ [ Build ▶ Test ▶ Review ]×N ──▶ Milestone demo ──▶ Release
      └──────── Gate A: docs approved ───────┘                           └─ Gate B per milestone ─┘
```

- **Gate A — Design approval:** requirements, architecture, ADRs and delivery plan approved.
- **Gate B — Milestone acceptance:** each milestone ends with a demo against its acceptance criteria.
- Changes to an approved requirement or ADR go through a **change request** (CR): a docs-only PR with a new ADR and/or
  requirement changes plus a change-log entry, approved by the product owner before implementation.

| CR | Title | Status |
|---|---|---|
| CR-001 | WhatsApp Safety Layer (ADR-0006, 04-safety-requirements) | Approved 2026-09-25 |
| CR-002 | Plan lock for Official WhatsApp and operator screen in Super Admin (ADR-0008, WW-FR-32/33) | Approved 2026-09-27 |
| CR-003 | Operator console design and per-client feature switches (ADR-0009, WW-FR-34) | Approved 2026-09-27 |
| CR-004 | One operator console: clients lifecycle, users, system health, settings; developer tools unlinked (ADR-0009 amendment, WW-FR-35) | Approved 2026-09-27 |

### Branching and pull requests

- `main` — the product. Always releasable. Changes only via pull request with green CI. (GitHub branch protection
  needs a paid plan for private repos, so this is a team rule: never push directly to `main`, never merge a red PR.)
- Feature PRs are **squash-merged**; `upstream-sync` PRs use a **merge commit** so Chatwoot's history is preserved.
- `feat/<scope>-<short-desc>`, `fix/...`, `chore/...` — one task per branch, one PR per task.
- `upstream` remote — `chatwoot/chatwoot`. Upstream updates arrive through `chore/upstream-sync-<version>` PRs.
- Commits follow Conventional Commits: `type(scope): subject` (e.g. `feat(engine): add QR session lifecycle`).
- Every PR describes *what / why / how tested* and links the requirement IDs it implements (e.g. `WW-FR-03`).

### Definition of Done (every task)

1. Code follows the repo style guides (`CLAUDE.md`, RuboCop, ESLint) and lints clean.
2. Automated tests cover the new behaviour; the whole affected suite passes in CI.
3. No secrets, credentials or personal data in code, logs or fixtures.
4. Docs/ADRs updated if behaviour or design changed.
5. PR reviewed and merged to `main`; requirement IDs ticked in the delivery plan.
6. The user journey is checked, not just the unit (rules from the
   [2026-09-27 device test](acceptance/M2-M4.md#bugs-found-root-cause-and-the-rule-that-prevents-the-class)):
   - **Test the entry point.** For anything user-facing, a test mounts the real parent page, route or tab the user
     opens it from, not only the component itself.
   - **Follow reused behaviour to what the user sees.** When reusing a Chatwoot mechanism (flags, notifications,
     jobs), check every place it is exposed (API JSON, sidebar, emails) and test the output for our channel.
   - **Realistic inputs.** Test data includes what real Indian customers and staff type (Hindi, Hinglish, typos,
     emoji) and real payloads (recorded fixtures), not just textbook examples.
   - **Test every transition.** For state machines (sessions, linking, sending), cover cancel, replace, expire and
     retry paths, and assert that after a cleanup nothing comes back.
   - **Run-mode smoke check.** Before a demo, run the same mode the demo uses and confirm the pieces reach each
     other (engine → Chatwoot webhooks, Chatwoot → engine) before handing over.

### Fork hygiene (keep upstream merges cheap)

- Prefer **new files** over editing Chatwoot files. When an upstream file must change, keep the edit minimal
  and list it in [02-architecture.md § Upstream touch points](02-architecture.md#upstream-touch-points).
- Never modify files under `enterprise/` (separate licence; see ADR-0001).
- Our non-Rails code lives in `wadesk-engine/` at the repo root.

## Local development

Everything runs in containers; nothing but Docker/Podman is needed on the laptop. `bin/wadesk-dev` wraps
`docker-compose.wadesk-dev.yaml` (Ruby 3.4.4, Node 24, pnpm 10 toolbox + Postgres + Redis, no host ports except the
dev server). On Fedora it uses the rootless Podman socket automatically.

| Command | Purpose |
|---|---|
| `bin/wadesk-dev setup` | First-time (and after dependency changes): build toolbox, install gems/packages, prepare dev + test DBs |
| `bin/wadesk-dev rspec spec/models/channel/whatsapp_spec.rb` | Run backend specs. They never build the frontend locally: specs that render full pages (e.g. Super Admin) use the bundle from `ui-bundle`, and fail fast without it |
| `bin/wadesk-dev rubocop app/models/channel/whatsapp.rb` | Lint Ruby |
| `bin/wadesk-dev pnpm test` / `bin/wadesk-dev pnpm eslint` | Frontend tests / lint |
| `bin/wadesk-dev sh` | Shell inside the toolbox |
| `bin/wadesk-dev server` | Chatwoot dev server on http://localhost:3300 (Vite on 3036) — needs a lot of memory |
| `bin/wadesk-dev ui-bundle` then `bin/wadesk-dev server-prebuilt` | Low-memory alternative: run the GitHub workflow **WaDesk UI bundle** (Actions → Run workflow) on your branch, download its frontend bundle, and run Chatwoot + engine without compiling the frontend |
| http://localhost:8025 | Mailpit: every email Chatwoot sends in development (e.g. "connection expired"); starts with `server` / `server-prebuilt` |
| `bin/wadesk-dev smoke` | With the stack running: check Chatwoot and the engine reach each other in the current mode. Run before every demo or device test |
| `bin/wadesk-dev down` | Stop everything (data volumes are kept) |

Engine commands are in [wadesk-engine/README.md](../../wadesk-engine/README.md).

**Migrations:** in dev the engine keeps its `wadesk_engine` schema in Chatwoot's database, so `rails db:migrate` dumps
an extra `create_schema "wadesk_engine"` (and may bump the `[7.1]` header or re-annotate models). Commit only the
new table/columns in `db/schema.rb`, keep the header as-is, and revert unrelated model annotations.

The laptop has limited memory: stop the demo stacks (`docker compose stop` in the demo folders) before heavy work
such as `setup` or the full spec suite.
