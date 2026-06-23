# Alert noise control: precision channel vs recall channel, with self-tuning promotion

Alert fatigue kills compliance tools: a finding that interrupts too often trains the
Auditor to ignore *all* Alerts, at which point a muted Alert is worse than none — it
manufactures false safety. So findings are split across two channels optimized for
opposite goals.

- **Recall channel — the Triage Queue.** *Every* finding opens a Case here. Nothing is
  lost; reviewed in the workbench and a periodic digest. Optimized to catch everything.
- **Precision channel — Alerts.** A finding is *promoted* to an interrupting Alert only
  if it clears a gate: (deterministic Severity ≥ critical OR Anomaly Score ≥ high) AND
  money-at-risk ≥ the Materiality Floor AND no matching Suppression Rule AND the Baseline
  is mature. Optimized so an Alert is almost always real.
- **Self-tuning demotion.** Per-rule Alert outcomes (actioned vs dismissed) are tracked.
  If a rule's Alert precision falls below target (e.g. <50% actioned), it is auto-demoted
  to Case-only and flagged for tuning. No single noisy rule may train users to ignore
  Alerts.
- **Dedup/grouping.** Findings sharing (vendor × rule × root-cause) collapse into one
  Case/Alert, not many.

## SLA / quality bars

- **Alert latency**: before the irreversible step (ADR-0003), seconds-to-minutes.
- **Alert precision target**: a measurable bar (e.g. ≥70% of Alerts actioned); breaching
  it triggers demotion/tuning.
- **Triage SLA**: Cases triaged within N days (configurable per Organization).

## Consequences

- The product is judged on Alert *precision*, not Alert *volume* — fewer, truer Alerts
  is the explicit goal.
- `dismissed` Case reasons (ADR-0008) feed both Suppression Rules and self-tuning.
