# Engine ↔ Chatwoot contract fixtures

Canonical examples of the webhook payloads the engine sends to Chatwoot
(docs/wadesk/02-architecture.md §4.2). **Both test suites use these files:** the engine's normalizer tests assert it
produces them exactly, and Chatwoot's specs feed them into the incoming pipeline. Changing a file changes the contract
for both sides — update the code and specs on both sides in the same PR.

| Folder | Event |
|---|---|
| `messages/` | `messages` events (Cloud API message shape), one file per message kind |
| `statuses/` | `statuses` events (delivery receipts), one status per event |
