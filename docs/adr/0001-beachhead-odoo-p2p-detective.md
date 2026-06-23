# Beachhead: Odoo · Procure-to-Pay · Detective read-only

To turn a broad idea ("AI Process Compliance Auditor that plugs into ERP") into a
shippable micro-SaaS, we deliberately narrow the first version to a single ERP, a
single business process, and a single posture toward the customer's data.

- **ERP: Odoo only.** Open API (XML-RPC/JSON-RPC), large SME/mid-market base
  (incl. Vietnam), short sales cycle. We explicitly reject SAP for v1 (highest pain
  but enterprise sales cycle and complex integration surface — wrong shape for a
  bootstrapped micro-SaaS).
- **Process: Procure-to-Pay (P2P).** Where money leaks most visibly and where the
  rules are *deterministic and verifiable* (document matching), not subjective. The
  wedge controls: 3-way match (PO ↔ Goods Receipt ↔ Vendor Bill), split-PO threshold
  evasion, duplicate invoice / duplicate vendor, payment without source document.
- **Posture: Detective, read-only.** v1 *reads* Odoo and flags violations *after*
  documents are posted. It automates the *investigation* workflow (finding → evidence
  → notification → triage), but never writes back to Odoo. Preventive enforcement
  (blocking/write-back) is a deferred opt-in module — we must *earn* the right to
  touch a customer's ERP by first proving detection accuracy.

## Considered Options

- Preventive write-back in v1 — rejected: trust barrier and legal liability of
  mutating a customer's ERP are the single biggest adoption blocker.
- Vietnamese local ERPs (MISA/Bravo/Fast) — rejected for v1: poor/closed APIs make
  the integration risk and data-normalization cost too high to start with.

## Consequences

- Ingestion is poll/read-oriented; no real-time blocking path exists in v1.
- The product is positioned as an *auditor* (observe + alert), not an enforcement gate.
- "Automation" in the product name means automated *detection & investigation*, not
  automated *remediation in the ERP* — see [[detective]] / [[preventive]] in CONTEXT.md.
