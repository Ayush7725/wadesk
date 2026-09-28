# Enterprise feature audit and plan

**Status:** approved by the product owner on 2026-09-28 (decisions in §7) · **Date:** 2026-09-28
**Scope:** every feature in Chatwoot's `enterprise/` directory in the exact version WaDesk runs; what WaDesk needs;
the licensing boundary; how WaDesk builds the needed features without using proprietary code.

> Not legal advice: this is the engineering team's reading of the licence files. Instead of a lawyer review, the
> product owner keeps the plan low-risk (§7): no enterprise code in production, clean-room features, MIT notice kept,
> full rebrand, a client agreement for WhatsApp Web risk.

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
2. **Enterprise-equivalent features are built clean-room by WaDesk** (product-owner decision, 2026-09-28):
   - Inputs are **public documentation, observed behaviour and the MIT parts only**. Nobody implementing a feature reads
     `enterprise/` code for it; enterprise code is never copied, translated or used as a template.
   - This audit was the one-off inventory (which features exist, where the MIT/proprietary line runs). Its file lists
     are for scoping, not for implementation.
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

## 5. Approved plan (one step at a time)

1. **P0 — Run without enterprise.** Production image without `enterprise/`; boot and rake tasks tolerate its absence;
   unguarded enterprise routes removed or guarded; views fall back to MIT templates; the full CE spec suite and the
   WaDesk suites green without it. Required by the licence; also stops the nightly branding reset.
2. **Rebrand**, done through the white-label settings wherever possible (installation name, brand name, logos, links,
   email sender), with code changes only where a setting doesn't exist (hard-coded texts, emails, icons).
3. Clean-room WaDesk versions of enterprise features, in this order:
   1. **Security setup** — 2FA (encryption keys), session limits, rate limits: configure and verify.
   2. **Voice-note transcription.**
   3. **AI writing help** (reply suggestions, rewrite, summary): switch on, with usage limits per client.
   4. **Audit logs.**
   5. **Custom roles and permissions.**
   6. **AI auto-reply bot with knowledge base** — needs a safety review for WhatsApp Web before it can answer there.
   7. **WhatsApp campaign analytics** — Official only, inside the WaDesk campaign rules (ADR-0006).
4. **Later:** SLA, smart assignment (capacity, least-busy), required conversation fields.
5. **Skipped for now:** SAML SSO, WhatsApp / Twilio calling, conversation monitors, advanced search.

Every feature follows the same definition of done (handbook rule 6) plus: backend + frontend + policy enforcement at
the API; validation and error handling; tenant-isolation specs (a second account must never read or change the first
account's data through any endpoint); regression runs of the affected CE suites; an end-to-end browser check; the
provenance record.

### Business and operating model (product-owner input, 2026-09-28)
- **WaDesk is sold by the product owner as an individual, as a hosted service:** clients get logins to WaDesk; the
  software itself is not distributed to them.
- **Monthly sync with Chatwoot updates:** a `chore/upstream-sync-<version>` PR each month (merge commit, per the
  handbook). Each sync re-checks that `enterprise/` stays out of the production image, reviews newly added upstream
  enterprise features and MIT files for the inventory above, and re-runs the full suites and the smoke check.
- **Rebrand through white-label settings wherever possible** (see step 2), so upstream syncs stay cheap.

## 6. Provenance record (template, one per feature PR)

| Field | Content |
|---|---|
| Original Chatwoot feature | name, version 4.18.0 |
| Sources used | public documentation (links), observed behaviour, MIT files (paths); `enterprise/` code not read for implementation |
| MIT parts reused | e.g. table, migration, screens, API shape — with paths |
| Code copied from `enterprise/` | **none** (any exception must be approved and justified in writing) |
| WaDesk implementation paths | new files / changed files |
| Behaviour differences | where WaDesk intentionally differs |
| Licence note | MIT parts keep their notice; WaDesk code is WaDesk-owned |

## 7. Product-owner decisions (2026-09-28)

1. **P0 approved:** remove `enterprise/` from the production image and make WaDesk run fully without it; then the rebrand.
2. **Priority order approved** as in §5 (it replaces the P columns in §4 where they differ).
3. **Clean-room rule:** public docs and behaviour only; never copying `enterprise/` code (§2).
4. **Added to the plan:** hosted service sold by an individual; monthly upstream sync; rebrand via white-label settings.

### Low-risk policy (product-owner decision, 2026-09-28, replaces the earlier lawyer-review item)
1. **No enterprise code in production** — `enterprise/` removed from the image completely (P0).
2. **Clean-room only** — enterprise-style features are built from public documentation and observed behaviour; nobody
   reads `enterprise/` code for them (§2).
3. **Chatwoot's MIT notice stays** — the `LICENSE` file (Chatwoot's copyright line and the MIT text) is never removed or
   edited; the rebrand changes what users see, not the licence. A spec guards the file.
4. **Full rebrand** — no Chatwoot name, logo or link visible to clients, their customers or the operator (acceptance
   check of the rebrand). Machine identifiers that integrations depend on (widget SDK names, webhook headers, database
   names) are not user-visible and stay.
5. **Number checker: single number only** — checking whether one number is on WhatsApp, done by an agent for one
   contact at a time; no bulk or list checking (it looks like contact harvesting, ADR-0006).
6. **Client agreement** — every WhatsApp Web client accepts the one-page agreement
   [templates/whatsapp-web-client-agreement.md](templates/whatsapp-web-client-agreement.md) (unofficial connection,
   possible bans, no liability for bans) before their Web number is linked.
