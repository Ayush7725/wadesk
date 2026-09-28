# Enterprise feature audit and plan

**Status:** audit complete, plan proposed — awaiting product-owner approval · **Date:** 2026-09-28
**Scope:** every feature in Chatwoot's `enterprise/` directory in the exact version WaDesk runs; what WaDesk needs;
the licensing boundary; how WaDesk builds the needed features without using proprietary code.

> Not legal advice. The licence reading below is the engineering team's; have a lawyer confirm it before WaDesk is
> sold commercially. The per-feature provenance records this document asks for are meant to make that review easy.

## 1. Version facts (from the checked-out source)

| Item | Value |
|---|---|
| Chatwoot version | 4.18.0 (`config/app.yml`, `package.json`) |
| Fork base | upstream `develop` @ `fa57193fe` (2026-09-25), after the `release/4.18.0` merge |
| WaDesk repository | `github.com/Ayush7725/wadesk`, branch `main`; `upstream` = `chatwoot/chatwoot` (fetch only) |
| WaDesk changes | 58 commits on top of the base; **`enterprise/` is unmodified** (`git diff fa57193fe HEAD -- enterprise` is empty) |
| Size | `enterprise/`: 560 files; `spec/enterprise/`: 296 files |

## 2. Licensing boundary

- `LICENSE`: everything **outside** `enterprise/` is MIT (Expat). That includes the whole Vue frontend in
  `app/javascript/**` (also the screens of Enterprise features), `db/migrate` and `db/schema.rb` (also the tables of
  Enterprise features), most routes, the base policies and the audited gem wiring.
- `enterprise/LICENSE`: the code may be used **in production only with a paid Chatwoot Enterprise licence**;
  modifications and patches also belong to Chatwoot; copying and modifying are allowed only **for development and
  testing**; copying, publishing, distributing, sublicensing and selling are otherwise forbidden.

**Consequences for WaDesk**
1. **WaDesk must not run Chatwoot's enterprise code in production.** Today the image contains `enterprise/` and
   `ChatwootApp.enterprise?` is true, so it runs. Setting `DISABLE_ENTERPRISE` is **not enough**: `config/application.rb`
   still eager-loads `enterprise/app/**`, puts `enterprise/app/views` in front of `app/views` (e.g. the Devise
   confirmation email template is the enterprise one) and requires the enterprise initializers; several routes without
   an `enterprise?` guard still reach enterprise controllers. The production image must **not contain `enterprise/`**.
   Evidence that WaDesk runs without it: our CI job `backend-targeted` deletes `enterprise/` and `spec/enterprise/`
   before running the specs.
2. **Enterprise-equivalent features are written by WaDesk.** Rules:
   - Enterprise code may be read to understand *behaviour* (what a user can do, edge cases). It is never copied,
     translated line by line, or used as a template for WaDesk code.
   - Each feature is specified first in WaDesk's own words (requirements + API contract), then implemented from that
     specification in WaDesk-owned code (`app/**/wadesk/**` or clearly marked WaDesk files).
   - MIT parts are reused freely: screens, tables, migrations, API shapes the MIT frontend expects, base policies.
   - Every feature PR carries a **provenance record** (§6).

## 3. How the enterprise code plugs in (summary)

- `lib/chatwoot_app.rb`: `enterprise?` is true when `enterprise/` exists and `DISABLE_ENTERPRISE` is unset (any value,
  even `false`, disables it). `extensions` drives `prepend_mod_with` / `include_mod_with`
  (`config/initializers/01_inject_enterprise_edition_module.rb`): 111 call sites in 97 core files.
- Routes guarded by `ChatwootApp.enterprise?`: monitors, campaign analytics, reporting events, calls, WhatsApp calls,
  CSAT review-note update, voice conference, access request, billing, Stripe / Firecrawl webhooks, Twilio voice.
  **Not guarded** (controllers only in `enterprise/`): `captain/*` (except `tasks`, `preferences`), `saml_settings`,
  `audit_logs`, `sla_policies`, `custom_roles`, `agent_capacity_policies`, `auth/saml_login`, custom-domain challenge.
- Frontend: `IS_ENTERPRISE` / `isEnterprise`, `PREMIUM_FEATURES`, `usePolicy` paywall logic; many Enterprise screens
  are restricted to `installationTypes: [CLOUD, ENTERPRISE]` and hidden on community installs.
- A daily production job (`CheckNewVersionsJob` + enterprise `ReconcilePlanConfigService`) resets branding and
  switches premium features off on every account when the plan is `community`. It cannot run once `enterprise/` is gone.

## 4. Feature inventory and decision

Legend — **Needed**: Yes / Later / No. **Implementation**: *Already MIT* (works without enterprise; configure or
extend), *Independent* (WaDesk writes the backend; reuses MIT screens/tables where the contract fits), *WaDesk-native*
(neither Chatwoot edition has it), *Not needed*. Priority P0 (first) … P4 (later).

| Feature | What it does | Enterprise backend | MIT parts already present | Needed | Implementation | P |
|---|---|---|---|---|---|---|
| **Run without enterprise** | Production image without `enterprise/`; boot, routes and views work | — | CI already runs without it | Yes | WaDesk change (image, boot guards, unguarded routes) | **P0** |
| Custom roles & permissions | Roles with permissions (conversation all / unassigned / participating, contacts, reports, knowledge base) that narrow access within inbox membership | `models/custom_role.rb`, `policies/enterprise/*`, `enterprise/…/permission_filter_service.rb`, `custom_roles_controller.rb` | `custom_roles` table, `account_users.custom_role_id`, permission list in `constants/permissions.js`, custom-roles screens, role pickers, frontend permission helpers | Yes | Independent: one permission resolver used by policies, conversation lists, unread counts and profile JSON; role CRUD; assignment on agents | P1 |
| Audit logs | Who did what to which object, when, from which IP | `models/enterprise/audit_log.rb`, `audit/*` modules, `audit_logs_controller.rb`, IP jobs | `audits` table and audited gem, audit-log screens and filters | Yes | Independent: WaDesk audit writer (model callbacks + explicit events: sign-in/out, deletions, plan/feature changes, WhatsApp link events, consent), account-scoped API | P1 |
| SLA | Policies (first/next response, resolution, business hours) on conversations; breach events, notifications, reports | `sla_policy.rb`, `applied_sla.rb`, `sla_event.rb`, `services/sla/*`, `jobs/sla/*`, SLA controllers | 3 SLA tables, `conversations.sla_policy_id`, SLA settings/badge/report screens, mail templates, activity messages | Yes | Independent (also fix: pause while snoozed/pending; start timers when the SLA is applied) | P2 |
| Advanced assignment | Per-agent capacity per inbox, balanced (least-busy) order, label/age exclusions | `agent_capacity_policy.rb`, `inbox_capacity_limit.rb`, `enterprise/auto_assignment/*` | Assignment v2 (round-robin, team, presence, rate limit) works; capacity tables and screens | Yes | Independent extension of MIT assignment v2 | P2 |
| Reports | Overview, conversations, agents, inboxes, teams, labels, CSAT, bots, live | SLA reports, raw event API, CSAT review notes, campaign analytics, monitors | Full CE reporting stack and screens | Yes | Already MIT; SLA reports with SLA; CSAT review notes Independent (small) | P2 / P3 |
| WhatsApp campaign analytics | Per-recipient sent / delivered / read / failed | `campaign_recipient.rb`, `enterprise/…/oneoff_campaign_service.rb`, analytics controller | `campaign_recipients` table; sending one-off campaigns is MIT | Yes (with WaDesk campaigns) | Independent, inside the WaDesk campaign system: Official only, opt-in, approval, audit (ADR-0006) | P2 |
| Plan limits | Caps on agents / inboxes per account | `plan_usage_and_limits.rb` | `accounts.limits`, `usage_limits` (never enforced in CE) | Yes | WaDesk-native, part of plans (operator console) | P2 |
| Security: 2FA, sessions, rate limits, password rules | TOTP 2FA and per-account enforcement, session list/revoke/limit, login throttling, strong passwords | — | **Already MIT** (needs Active Record encryption keys set for 2FA) | Yes | Configure and verify in the release checklist | P1 (config) |
| Device verification | Email code for logins from new devices | `device_verification*` (cloud only) | stub guard, trusted-devices endpoint | Later | Independent if wanted | P3 |
| IP allow / block lists per client | Restrict logins by IP | none in either edition | only rate-limit safelist | Later | WaDesk-native if a client asks | P4 |
| Agent schedules / shifts | Per-agent working hours | none in either edition (only inbox business hours) | inbox `working_hours`, availability + auto-offline | Later | WaDesk-native | P3 |
| SAML SSO | Per-account IdP login, group-to-role mapping | `account_saml_settings.rb`, SAML controllers, builder, OmniAuth setup | table, screens | Later (larger clients) | Independent | P4 |
| AI writing help (Captain tasks) | Reply suggestion, rewrite / tone, summary, label suggestion | only metering + doc search | **Backend MIT**; needs an OpenAI-compatible key | Yes | Already MIT + WaDesk usage metering and plan gating | P2 |
| Voice-note transcription | Text of WhatsApp voice notes | `audio_transcription*` | attachment model | Yes | Independent | P2 |
| AI assistant (auto-reply bot, knowledge base, handoff, FAQ mining, copilot) | Bot answers customers from documents / FAQs and hands off | `captain/**` (large) | 12+ tables with pgvector, all screens | Later | Independent, its own change request; auto-replies on WhatsApp Web need a safety review | P3 |
| WhatsApp calling (Official) | Browser calls over WhatsApp Cloud | `whatsapp/*call*`, `whatsapp_cloud_service.rb` | channel methods, call screens | Later | Independent, Official only | P4 |
| Twilio voice | Phone calls | `services/voice/**` | tables, screens | No | Not needed | — |
| Conversation monitors | Natural-language alerts via a proprietary "jev" model | `conversation_monitors/*` | tables, screens | No (for now) | Not needed; revisit with WaDesk's own LLM | — |
| Required conversation attributes | Block resolve until fields are filled | macro enforcement | UI check | Later | Independent (small) | P3 |
| Advanced search (OpenSearch) | Full-text message search | `enterprise/search_service.rb` | searchkick hooks | No (for now) | Not needed | — |
| Help-center AI, embedding search, custom-domain SSL | Article translation, semantic portal search, Cloudflare SSL | onboarding / articles / cloudflare services | help center (MIT) | No (for now) | Not needed | — |
| Branding / "Powered by" removal | Custom name and logos; hide "Powered by" | enterprise only *resets* it | enforcement is MIT | Yes | Already MIT once enterprise is gone; part of the rebrand | P1 (rebrand) |
| Chatwoot billing (Stripe), cloud internals, hub sync | Chatwoot's own SaaS operations | `billing/*`, `internal/*` | — | No | Not needed (WaDesk has its own billing, Step 2) | — |

## 5. Proposed plan (one feature at a time)

1. **P0 — Run without enterprise.** Production image without `enterprise/`; boot and rake tasks tolerate its absence;
   unguarded enterprise routes removed or guarded; views fall back to MIT templates; the full CE spec suite and the
   WaDesk suites green without it. Unblocks the rebrand (branding no longer reset) and is required by the licence.
2. **P1 — Rebrand** (roadmap step 2), now possible.
3. **P1 — Security configuration**: 2FA encryption keys, session limits, rate limits verified in staging.
4. **P1 — Custom roles & permissions** (independent), then **audit logs** (independent). Every later feature writes to
   the audit log and checks permissions through the same resolver.
5. **P2** — SLA; advanced assignment; plan limits; WhatsApp campaign analytics with WaDesk campaigns; AI writing help
   metering; voice-note transcription; CSAT review notes.
6. **P3/P4** — agent schedules, device verification, required attributes, AI assistant, SAML, WhatsApp calling, IP lists.

Every feature follows the same definition of done (handbook rule 6) plus: backend + frontend + policy enforcement at
the API; validation and error handling; tenant-isolation specs (a second account must never read or change the first
account's data through any endpoint); regression runs of the affected CE suites; an end-to-end browser check; the
provenance record.

This ordering and the product boundary (ADR-0006: WhatsApp Web stays conversations-only; campaigns Official-only with
opt-in, approval and audit) are recorded as a change request once approved.

## 6. Provenance record (template, one per feature PR)

| Field | Content |
|---|---|
| Original Chatwoot feature | name, version 4.18.0 |
| Enterprise paths studied | files read for behaviour only |
| MIT parts reused | e.g. table, migration, screens, API shape — with paths |
| Code copied from `enterprise/` | **none** (any exception must be approved and justified in writing) |
| WaDesk implementation paths | new files / changed files |
| Behaviour differences | where WaDesk intentionally differs |
| Licence note | MIT parts keep their notice; WaDesk code is WaDesk-owned |

## 7. Decisions needed from the product owner

1. Approve **P0: remove `enterprise/` from the production image** (required by the licence; also fixes the branding reset).
2. Approve the **Needed / Priority** columns in §4 (change any "Later"/"No" you want sooner).
3. Arrange a **lawyer review** of §2 before commercial launch.
