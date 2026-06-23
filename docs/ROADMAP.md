# Roadmap — deliberately deferred past v1

Everything here was a *conscious* "not yet" during design, not an oversight. Each item
notes why it was deferred and where the decision was made. v1 scope = Odoo · P2P ·
detective read-only · conformance + rule library · independent evidence ledger ·
statistical anomalies · read-only MCP · schema-per-tenant · audit-readiness deliverable.

## Fast-follow (the very next things after v1)

- **NL Control authoring.** Customer writes a policy in plain language → AI compiles it
  to a deterministic Control → human approves before activation. Deferred because the
  pre-built template library must mature first to have something correct to compile
  *into* (Câu 13). v1 ships parameterized Control Templates only.
- **Customer-tunable false-positive suppression.** `dismissed` Cases already carry a
  reason; turning that into systematic rule/baseline tuning is post-v1 (ADR-0008).

## Deferred (clear future, not imminent)

- **Preventive enforcement / write-back module.** Blocking, freezing, or altering Odoo
  transactions. Must be a *separately-credentialed* module — the v1 read-only credential
  (ADR-0007) makes this impossible by accident. See ADR-0001, ADR-0002.
- **Heavy ML for Layer 2.** Isolation Forest / Autoencoders / vector embeddings, once
  simple statistics (percentile/z-score) prove insufficient. See ADR-0006.
- **CDC ingestion.** Real-time logical replication / Debezium from Odoo's Postgres, for
  customers who self-host and want sub-second capture. See ADR-0003.
- **MCP write/triage actions.** Acknowledging Alerts and changing Case status from an AI
  assistant, beyond v1's read-only query surface. See Câu 10.
- **Public-CA Digital Signature (chữ ký số) — Enterprise add-on.** Remote/Cloud CA
  (Viettel MySign / FPT SmartCA) signing of exported PDF Audit Reports for court-grade
  non-repudiation (threat Tier C). v1 ships internal Attestation + hash-chain + external
  anchor only. See ADR-0009.

## Horizon (the long-term moat / expansion)

- **General process-mining platform.** Customer-authored Process models and general
  event-log mining, beyond the one pre-built P2P model. See ADR-0004.
- **More processes.** Order-to-Cash, standalone Segregation-of-Duties, etc., beyond P2P.
- **More ERPs.** SAP, NetSuite, Dynamics, Vietnamese local ERPs, beyond Odoo. See
  ADR-0001.
- **Data-residency / multi-region** options for the evidence ledger. See ADR-0005.
