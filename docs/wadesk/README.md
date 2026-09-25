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
| [adr/](adr/) | Architecture Decision Records — one file per significant decision | See index below |

### ADR index

| # | Decision | Status |
|---|---|---|
| [0001](adr/0001-fork-chatwoot.md) | Build the product as a fork of Chatwoot | Accepted |
| [0002](adr/0002-whatsapp-web-engine-sidecar.md) | WhatsApp Web runs in an internal Node sidecar built on Baileys | Accepted |
| [0003](adr/0003-baileys-as-chatwoot-provider.md) | Integrate as a `baileys` provider of `Channel::Whatsapp`, reusing the incoming pipeline | Accepted |
| [0004](adr/0004-session-state-in-postgres.md) | Store WhatsApp session credentials in Postgres | Accepted |
| [0005](adr/0005-plan-gating-with-feature-flags.md) | Gate channel types per account with Chatwoot feature flags | Accepted |

## Development process (SDLC)

We follow a gated, iterative lifecycle. Each gate requires product-owner approval before work continues.

```
 Requirements ──▶ Design ──▶ Plan ──▶ [ Build ▶ Test ▶ Review ]×N ──▶ Milestone demo ──▶ Release
      └──────── Gate A: docs approved ───────┘                           └─ Gate B per milestone ─┘
```

- **Gate A — Design approval:** requirements, architecture, ADRs and delivery plan approved.
- **Gate B — Milestone acceptance:** each milestone ends with a demo against its acceptance criteria.
- Changes to an approved requirement or ADR go through a new ADR (or a revision marked in the doc), never silently.

### Branching and pull requests

- `main` — the product. Always releasable. Protected: changes only via pull request with green CI.
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

### Fork hygiene (keep upstream merges cheap)

- Prefer **new files** over editing Chatwoot files. When an upstream file must change, keep the edit minimal
  and list it in [02-architecture.md § Upstream touch points](02-architecture.md#upstream-touch-points).
- Never modify files under `enterprise/` (separate licence; see ADR-0001).
- Our non-Rails code lives in `wadesk-engine/` at the repo root.
