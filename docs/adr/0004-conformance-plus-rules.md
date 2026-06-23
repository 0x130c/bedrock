# Process compliance = conformance against one pre-built P2P model + a rule library

To genuinely earn the name "Process Compliance" (not just "transaction compliance")
without taking on a general process-mining platform, v1 models the expected
Procure-to-Pay process explicitly and checks each real instance against it, alongside
a library of atomic rules.

- **One opinionated, pre-built Process model.** The canonical P2P happy path
  (PR → PO → approval → Goods Receipt → Vendor Bill → 3-way match → Payment) is
  encoded as a state machine (`ash_state_machine`). Customers do *not* author their
  own process models in v1.
- **Conformance checking.** Each PO's actual journey is reconstructed from Odoo into
  a Process Instance and compared against the model. Divergences (skipped step,
  out-of-order, unauthorized shortcut, abnormal rework loop) become Conformance
  Deviations.
- **Atomic rule library coexists.** Threshold/split-PO, duplicate invoice/vendor,
  SoD, etc. produce Rule Violations.
- **Layer 2 Anomalies** (behavioral outliers) round out the three finding types.

A Case can be opened by any of: a Rule Violation, a Conformance Deviation, or an
Anomaly.

## Considered Options

- General process-mining platform with customer-authored models — rejected for v1:
  event-log reconstruction + model authoring + conformance algorithms is too heavy
  for a bootstrapped micro-SaaS. It is the long-term moat, not the starting point.
- Atomic rules only — rejected as the v1 floor: it cannot catch flow violations
  (skipped approval, receive-after-pay) and would make "Process" in the name hollow.

## Consequences

- **Term collision resolved.** "Case" = the investigation record (human-facing).
  "Process Instance" = one PO's actual reconstructed journey. They are never synonyms.
- Reconstructing a Process Instance requires an ordered event log per PO from Odoo —
  reinforcing the evidence-snapshotting need from ADR-0003 (we cannot trust the ERP to
  retain ordered history).
