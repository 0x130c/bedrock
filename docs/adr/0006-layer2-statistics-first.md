# Layer 2 starts as lightweight statistics, not heavy ML

The Anomaly Detection Engine (Layer 2) ships in v1 as simple statistical baselines —
percentile / z-score on timing, amount, and frequency — not Isolation Forest /
Autoencoders / embeddings. Heavy ML is deferred until simple statistics prove
insufficient.

- The flagship anomaly example ("shorter than 99.8% of normal transactions") is a
  *percentile*, achievable without heavy ML.
- **Cold-start is solved by backfill**: at onboarding, Bedrock polls 6–12 months of
  Odoo history via API to compute an immediate Baseline, so statistical anomaly
  detection works from day one rather than after weeks of accumulation.
- Heavy ML would demand ML infra unnatural to an Elixir/Ash stack (Nx/Axon or a Python
  sidecar) — disproportionate cost and risk for v1.
- Layers 1 (rules + conformance) and 3 (LLM Narrative) are already a complete, sellable
  product that demos on day one with no history; Layer 2 statistics add behavioral
  reach cheaply.

## Consequences

- "AI" in the product is not gated on heavy ML for v1 — the deterministic Engine and
  the LLM Context Weaver carry the launch; Layer 2 grows in sophistication later.
- Onboarding must include a historical backfill step (and its data-residency
  implications, see ADR-0005).
