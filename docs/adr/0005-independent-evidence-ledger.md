# Hard Evidence lives in an independent, append-only ledger outside the ERP

Hard Evidence is what the Auditor signs the report on, so its integrity is the product's
credibility. Because Bedrock is read-only and partly poll-based, it cannot rely on the
ERP to retain truthful history — a privileged insider can alter or erase the ERP's own
trail. Bedrock therefore keeps its own evidence.

- **Independent immutable ledger.** Captured evidence is written append-only,
  encrypted at rest (`ash_events` + `ash_paper_trail` + `cloak`) inside Bedrock. Once
  written it is frozen, even if the source ERP record later changes.
- **Three feed sources.** (1) Snapshot at detection time for state checks; (2)
  reconstruction of before/after diffs from Odoo's own field-tracking
  (`mail.tracking.value`) via polling; (3) push webhooks on hot fields for real-time,
  tamper-resistant capture.
- **Positioning.** Evidence is trustworthy *precisely because it sits outside the ERP
  the suspect may control.* This is a core "why a separate tool" argument, not just an
  implementation detail.

## Consequences

- **Accepted limitation (documented honestly).** Pure polling can miss a sub-interval
  transient state — e.g. bank account X→Y→X entirely between two polls. Push on hot
  fields and Odoo's own field-tracking mitigate this but do not eliminate it. We state
  this plainly rather than overclaim.
- Storing customer financial data outside their ERP raises a data-residency / trust
  obligation that onboarding and the tenancy model must address (to be decided).
