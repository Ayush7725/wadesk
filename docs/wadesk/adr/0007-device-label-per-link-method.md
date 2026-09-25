# ADR-0007: Device label depends on how the number is linked

- **Status:** Accepted (product owner, 2026-09-25) · **Date:** 2026-09-25

## Context
A linked WhatsApp Web session appears under *Linked devices* on the business's phone with a label the client sends
("browser (OS)"). We label it **"WaDesk"** so businesses can recognise it (SAFE-FR-05 spirit: be transparent).

M1 acceptance on a real phone showed that WhatsApp's **pairing-code** flow ("Link with phone number instead")
rejects custom labels — linking fails with "couldn't link" — while the QR flow accepts them. With a standard label
("Chrome (Ubuntu)") pairing codes link within seconds. Pairing codes matter for phone-only business owners, who
cannot scan a QR code shown on the same phone.

## Decision
- **QR links** keep the label **"WaDesk"**.
- **Pairing-code links** use the standard label **"Chrome (Ubuntu)"**; the setup screen (M4) tells the admin that the
  device will appear under that name.
- The label is chosen per session from its stored `link_method` and kept for later reconnects.

## Consequences
- ✅ Both linking methods work; phone-only owners can connect.
- ⚠️ Code-linked devices are less recognisable on the phone; mitigated by explicit UI copy.
- This is not detection evasion (ADR-0006 decision 3): the label is required by WhatsApp's flow, and the admin is told.

## Alternatives considered
- **Always "WaDesk", QR only** — clearest name, but excludes phone-only owners.
- **Always a standard label** — simplest, but businesses cannot tell which linked device is WaDesk.
