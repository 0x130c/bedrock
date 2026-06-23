# Audit Report integrity: internal Attestation + hash-chained, externally-anchored ledger

The headline deliverable's credibility rests on two claims that must not overclaim: that
a human stands behind the decision, and that the record cannot be silently altered. We
make each claim only as strongly as the v1 mechanism actually supports.

- **v1 "signing" is Attestation, not a Digital Signature.** The Auditor's approval is an
  internal, identity-bound assertion that they reviewed the Hard Evidence and decided.
  It carries no public-CA certificate (chữ ký số) and makes no claim to statutory
  e-signature weight. Court-grade non-repudiation needs a public-CA Digital Signature —
  a deferred Enterprise add-on (Remote/Cloud CA: Viettel MySign / FPT SmartCA on an
  exported PDF), see ROADMAP.
- **Attestation is scoped to the human's decision over the Hard Evidence.** The AI
  Narrative is bundled and hashed for integrity but is never the thing attested —
  preserving the Investigator-not-Judge invariant (CONTEXT.md, Câu 4).
- **Tamper-evidence = hash-chain + external anchor.** Each closed Case is serialized to
  canonical JSON (Hard Evidence + AI Narrative + Attestation), SHA-256 hashed, and
  *chained* (each hash includes the prior chain head). The chain head is *anchored
  outside Bedrock's mutable DB* — periodic automated email to the customer plus an
  RFC-3161 trusted timestamp.

## Threat tiers (state the claim precisely)

- **A — ERP fraudster** with no Bedrock access: beaten by the separate ledger alone
  (ADR-0005). The hash is almost redundant here.
- **B — privileged insider** who can reach Bedrock's DB (a Bedrock admin, colluding
  customer IT): a lone in-DB hash does *not* stop them (they recompute and overwrite).
  The hash-chain + external anchor is what makes "even a Bedrock admin can't silently
  alter it" an *honest* claim. This is the v1 target.
- **C — court-grade non-repudiation**: requires the public-CA Digital Signature add-on.

## Consequences

- **Marketing is constrained to "tamper-evident (Tier B)", never "tamper-proof".**
  Overclaiming on the one feature the whole trust story depends on is forbidden.
- Hashing requires a canonical JSON serialization (stable key order, fixed number/date
  formats) for reproducibility.
- The Enterprise CA add-on layers cleanly on top of the exported Audit Report PDF.
