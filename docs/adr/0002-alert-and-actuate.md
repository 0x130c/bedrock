# Alert-and-actuate: Bedrock signals, the customer acts

ADR-0001 makes Bedrock read-only toward the ERP, yet the most valuable fraud cases
need a transaction *stopped* before money moves. We resolve this without giving
Bedrock write access: Bedrock realizes preventive value purely by **signalling**.

- When a Violation or high-score Anomaly warrants it, Bedrock emits a low-latency
  **Alert** (Slack / Telegram / SMS / webhook / API).
- Any actual write — freezing the order, holding the payment — is performed on the
  **customer's side of the boundary**: either a human pressing the button in the ERP,
  or the customer's *own* ERP automation reacting to Bedrock's webhook.
- Bedrock is an **event source**; the customer owns the **Actuator**. Bedrock never
  freezes, never writes.

## Consequences

- The legal/operational liability of stopping a real transaction stays on the
  customer's side, where it belongs. Bedrock's authority never exceeds surfacing and
  explaining (consistent with [[human-in-the-loop]]).
- "Freeze & Review" is therefore *not* a Bedrock capability — it is a customer-side
  reaction pattern that Bedrock enables.
- A latency requirement is created: an Alert is only useful if it arrives before the
  irreversible step (the payment leaving the bank). This drives the ingestion design
  (see ADR-0003 once decided) — at least the "hot" events cannot rely on slow batch
  polling.
