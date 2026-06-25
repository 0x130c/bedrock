# Cross-batch correlation via a persisted Event History, not single-batch detection

Detection (Layer-1 Controls, Conformance, Layer-2 Anomalies) originally correlated only the
records inside a single `ingest_events` call. Under the v1 poller (Slice 10, #11) one P2P
process is naturally split across many polls, so the flagship anomaly (`bank-change → payment`,
whose normal window is 5–15 days) never fires and Conformance emits false positives on partial
journeys. v1 persists every normalized Event and feeds each *pure* detector the relevant recent
history, so correlation spans batches while the detectors stay parameter-free (ADR-0006). This
substrate is a blocking prerequisite of #11 and closes #20, #21, #22, #23.

- **Persisted Event History.** Every normalized `Event` is upserted into a tenant-scoped store
  (ADR-0007 schema), keyed by a *semantic* natural key the normalizer assigns — `{model, odoo_id}`
  for entities/discrete facts, `{vendor_id, field, occurred_at}` for change facts — **not** the
  source-row id, so the same real-world fact arriving via poll and via webhook deduplicates.
  Upsert-latest; no version history in v1.
- **Replay, not stateful detectors.** Each ingest runs two phases: (1) normalize + upsert the
  whole batch into the Event History; (2) for each *touched* entity, load a bounded correlation
  window and run the existing pure functions over it. Every Control/detector declares its
  `{correlation key, lookback}`; `:full` (entity-complete, e.g. a whole journey) is capped at
  12 months. Re-evaluation of late events is inherent — no separate mechanism.
- **Idempotent findings.** Each finding carries a deterministic, *Episode*-grained `finding_key`
  it owns; a `Case` is unique on `{finding_type, finding_key}`, so re-ingestion and re-evaluation
  are no-ops. A `ProcessInstance` is a `{po_ref}` projection, upsert-latest. Evidence accretes
  **append-only** (a growing Episode appends new `HardEvidence`, never mutates prior — preserving
  the ADR-0005 hash-chain).
- **Monotonic-safe Conformance.** Only deviations that are stable under future appends are
  emitted: ordering / forbidden-step deviations immediately; omissions only once the Process
  Instance reaches a *terminal* state. Nothing is ever retracted.
- **Closure-aware dedup.** A `dismissed` / `accepted_risk` Episode stays suppressed; a `confirmed`
  Episode that keeps producing evidence **re-surfaces** (so handling a fraud never blinds us to it
  continuing); final closure of a resolution is gated by Episode terminality. This is a contract
  Slice 6 (#7) must honor.
- **Field contract pinned at the seam.** The normalizer coerces monetary fields to `Money`
  (`ash_money`) and quantities to `Decimal`, validates types, and **quarantines** bad records
  (visible data-quality signal) instead of crashing the batch; Controls evaluate per-currency
  (no cross-currency conversion in v1).

## Considered Options

- **Carry-forward per-entity state** (e.g. "last bank change per vendor") — rejected: breaks
  detector purity, needs new plumbing for every new pattern, and is fragile under out-of-order
  arrival, which an incremental poller guarantees.
- **Append-versions / full event-sourcing** — deferred: it is the natural fit for CDC (a change
  stream), but no v1 detector needs version history, and it would double-count the same fact seen
  via both poll and webhook. Upsert-latest deduplicates across the hybrid v1 (ADR-0003) and does
  not block adding an append side later if CDC or a version-history detector arrives.
- **Keep single-batch detection; ship the poller with a known-limitations note** — rejected: it
  silently disables the headline Layer-2 capability and trains Auditors to distrust Alerts, the
  existential risk ADR-0010 exists to prevent.
- **One fixed global correlation window** — rejected: simultaneously too short for a long journey
  (Conformance false positives) and too wide for split-PO (72h).

## Consequences

- A new dedicated foundational slice (normalizer → `Event` / Event History → idempotency →
  replay) lands *before* #11; split PR-A (normalizer + Event History + idempotency, #23/#22) and
  PR-B (replay + monotonic-safe conformance, #20/#21), each with regression tests that split a
  process across *separate* `ingest_events` calls.
- Storage and per-batch CPU cost, bounded by touched-entity windows, the 12-month `:full` cap,
  and an ~18-month Event History retention/prune (must exceed the 6–12 month backfill window).
- Controls and detectors shed their defensive type guards — they read one known shape.
- Slice 6 (#7) must implement the closure-aware dedup contract (terminality gate, `dismissed`
  vs `confirmed` asymmetry).
- Preventive "Alert beats the payment" stays best-effort via the optional webhook; detection
  *correctness* remains poll-backed, preserving the Detective posture (ADR-0001) and graceful
  degradation (ADR-0003).
