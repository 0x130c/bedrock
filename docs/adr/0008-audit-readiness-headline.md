# v1 headline: continuous control assurance, with fraud alerting as the hook

Two value narratives competed for the v1 headline: fraud loss-prevention (dramatic but
episodic, weak renewal driver) and audit-readiness / continuous control assurance
(universal, recurring, the renewal reason). We lead with the latter — it is on-target
with the product's name ("Process Compliance *Auditor*") and every company faces audit
pressure, whereas active fraud is rare.

- **Headline deliverable: the Audit Report** — a signed, immutable, exportable Case
  record (Hard Evidence + the Auditor's decision + signer + timestamp), plus a Control
  Coverage view showing which Controls are active and passing.
- **Fraud Alerts are the acquisition hook** — the "wow" demo that gets attention, not
  the reason to renew.
- **Case lifecycle** (`ash_state_machine`):
  `open → triaged → investigating → (confirmed | dismissed | accepted_risk) → closed
  → exported`. A `dismissed` Case carries a reason that feeds rule/baseline tuning.

## Consequences

- The product sells on recurring assurance value; the Audit Report export must be
  defensible enough to hand to an external auditor — which is exactly why evidence
  lives in an independent, immutable ledger (ADR-0005).
- Marketing keeps one focused message (assurance) rather than splitting attention.
