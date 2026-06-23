# Hybrid ingestion: polling floor + push accelerator

Bedrock needs Odoo data at two very different latencies: bulk reconciliation rules
(3-way match, duplicate scans) tolerate minutes/hours, while a few high-risk events
must alert before the irreversible step (payment leaving the bank). The "milestone
latency" instinct (literal milliseconds) is rejected as the wrong target — the real
deadline is *before the irreversible business step*, typically seconds-to-minutes
because payments run in batches.

- **Polling is the universal floor.** A scheduled Oban job pulls the Odoo API
  (XML-RPC/JSON-RPC) using a read-only API key. Works on *every* Odoo hosting,
  including Odoo Online SaaS. This is the lowest-friction onboarding and guarantees
  detective coverage even with zero customer-side install.
- **Push is an optional accelerator.** Where the customer's Odoo allows it
  (Automated Action + webhook on v17+, or a thin Bedrock module on self-host/Odoo.sh),
  a small set of *hot events* (vendor bank-account change, payment about to post, PO
  state change) is pushed to a Bedrock webhook for near-real-time Alerts.
- **Graceful degradation.** No push available → batch detective still works; only
  real-time alerting is lost.
- **CDC deferred.** True real-time via logical replication / Debezium from Odoo's
  Postgres is roadmap only — it requires DB access (self-host), is brittle across
  schema versions, and carries heavy ops for v1.

## Consequences

- Onboarding can start with nothing but a read-only API key; the webhook module is an
  upsell for customers who want real-time alerting.
- Because ingestion is read-only and partly batch, Bedrock cannot rely on the ERP to
  retain history — evidence must be snapshotted at detection time (to be decided
  separately).
