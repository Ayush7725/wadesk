# ADR-0001: Build the product as a fork of Chatwoot

- **Status:** Accepted · **Date:** 2026-09-25

## Context
WaDesk needs a multi-tenant shared inbox with contacts, assignment, automations, reports and the official
WhatsApp Cloud API channel. Building this from scratch would take many months before the first sale.
Chatwoot provides all of it under the MIT licence (except the `enterprise/` directory, which has its own licence).

## Decision
Fork Chatwoot (`upstream` = `chatwoot/chatwoot`) and build WaDesk on top. Our product lives on `main`.
We never modify or rely on `enterprise/` features. We keep changes additive and track every upstream file we edit.

## Consequences
- ✅ Fastest path to a sellable product; inherits a mature, tested inbox.
- ✅ MIT allows commercial use and rebranding (MIT copyright notice must be kept in the source).
- ⚠️ Upstream merges become our responsibility; mitigated by the touch-point list and `upstream-sync` PRs.
- ⚠️ We inherit Chatwoot's stack (Rails, Vue, Sidekiq) and its resource footprint.

## Alternatives considered
- **Custom app from scratch** — full control, but 2–4 months before first sale. Rejected for now.
- **Chatwoot + Evolution API side by side** — works today, but two products to operate, brand and license. Being replaced by this plan.
