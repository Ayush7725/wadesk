# ADR-0008: Operator screen in Super Admin; plans as create-only feature flags

- **Status:** Accepted (Change request CR-002, approved 2026-09-27) · **Date:** 2026-09-27

## Context
WaDesk sells three plans per client account: WhatsApp **Official**, WhatsApp **Web**, or **Both**. Two gaps blocked the
first paying client:

- Only WhatsApp Web was locked per account (`whatsapp_web` flag, WW-FR-30). Official WhatsApp (Cloud API, 360dialog,
  Twilio WhatsApp) was open to every account, so a Web-only client could add Official without paying for it.
- WaDesk runs without Chatwoot's enterprise edition (ADR-0001). Super Admin only shows account features and limits when
  `ChatwootApp.enterprise?`, so the operator had no screen to switch plans or set the daily new-chat limit
  (SAFE-FR-02); it was done in the Rails console. There was also no overview of WhatsApp Web numbers (WW-FR-31).

## Decision
1. **The operator screen lives in Chatwoot's Super Admin**, as two WaDesk pages: *WaDesk clients* (plan switches and the
   daily new-chat limit per account) and *WhatsApp Web numbers* (every Web number of every client with its connection
   state). Same login and access rule as the rest of Super Admin (super admins only); no separate app.
2. **Plans are feature flags**: `whatsapp_official` (new) and `whatsapp_web` (existing). "Both" means both flags on.
   `whatsapp_official` is on by default for new accounts and was switched on for all existing accounts, so nobody
   loses a channel they already use.
3. **Flags gate creation only.** Without the flag, a new inbox of that type is refused at the model (422 at the API)
   and not offered in the UI. Turning a flag off never breaks existing inboxes: they keep receiving, sending and
   saving connection updates. The operator screen says so and shows how many such inboxes the client has.
4. The WhatsApp Web numbers page reads the state Chatwoot already stores from engine webhooks; it does not call the
   engine, so it stays fast and works while the engine is down.

## Consequences
- The operator can onboard a client and change their plan without the console.
- Downgrading a client does not remove existing inboxes; removing them is a separate, deliberate action by the client
  or operator (to be covered by Step 2 suspension/billing work).
- Upstream Super Admin files get small additions (route and navigation entries); listed in
  [02-architecture.md § Upstream touch points](../02-architecture.md#upstream-touch-points).
