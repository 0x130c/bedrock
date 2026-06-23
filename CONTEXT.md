# Bedrock — AI Process Compliance Auditor

A micro-SaaS that plugs into a customer's ERP (Odoo first) and audits whether
business processes follow the rules. It *observes and explains*; the human auditor
decides. The product is an augmented microscope for audit teams, not a robot that
replaces them.

## Language

### Detection architecture (the 3 layers)

**Deterministic Engine** (Layer 1):
The rule-execution core, written in Elixir/Ash. Evaluates ĐÚNG/SAI compliance rules
against ERP data and produces verdicts that are 100% explainable and reproducible.
The source of truth for whether something is a Violation. Uses no AI.
_Avoid_: rule engine (when ambiguous), AI layer

**Anomaly Detection Engine** (Layer 2):
Behavioral analytics (traditional ML — Isolation Forest, Autoencoders — or vector
embeddings), not an LLM. Scores how far a sequence of actions deviates from a
Baseline and flags outliers. Produces suspicion, never a verdict.
_Avoid_: AI judge, LLM detector

**Context Weaver** (Layer 3):
The LLM. Given Hard Evidence gathered by Layers 1–2 (via RAG), it writes a
human-readable AI Narrative. It explains and summarizes; it never decides logic or
issues a verdict.
_Avoid_: AI brain, reasoning engine

**Anomaly Score**:
A 0–100% number from the Anomaly Detection Engine expressing how unusual a behavior
is relative to its Baseline. A suspicion signal, not a verdict.

**Baseline**:
The learned "normal" trajectory of behavior (timing, frequency, sequence) for a
user, vendor, or process, against which the Anomaly Detection Engine measures
deviation.

### Compliance concepts

**Control**:
The umbrella term (audit vocabulary) for any automated compliance check Bedrock runs —
a Compliance Rule or a Conformance check. What an external auditor calls a "control".

**Compliance Rule**:
A deterministic, ĐÚNG/SAI policy evaluated by the Deterministic Engine
(e.g. "PO > 500M must carry a CFO signature"). One kind of Control. Derived from the
customer's SOP.
_Avoid_: check, constraint

**Control Template**:
A pre-built, opinionated Control shipped by Bedrock that a customer activates and
*parameterizes* (thresholds, approver roles, currency tolerances, exempt vendors) via
UI — without writing logic. The v1 authoring model; NL-authored custom Controls are
deferred (see ROADMAP).
_Avoid_: preset, blueprint

**Process**:
The expected shape of a business process, encoded as a state machine (the canonical
P2P happy path: PR → PO → approval → Goods Receipt → Vendor Bill → 3-way match →
Payment). The "correct" path that real journeys are judged against. In v1 it is
pre-built and opinionated, not customer-authored. See ADR-0004.
_Avoid_: workflow, flow (unqualified)

**Process Instance**:
The actual journey of one concrete object (e.g. one PO) reconstructed from Odoo's
event log as an ordered sequence of activities. Compared against the Process to find
Conformance Deviations. NOT a Case.
_Avoid_: case (means the investigation record), trace (acceptable synonym, but prefer this)

**Violation**:
A confirmed deterministic breach of a Compliance Rule, produced by Layer 1. Binary
and explainable ("breached Rule 5: missing CFO signature"). One of the three finding
types that can open a Case.
_Avoid_: error, exception, flag

**Conformance Deviation**:
A deterministic divergence of a Process Instance from the expected Process — a skipped
step, out-of-order activity, unauthorized shortcut, or abnormal rework loop. A Layer-1
finding, sibling to a Violation. The "flow" half of process compliance. See ADR-0004.
_Avoid_: violation (reserve that for rule breaches), deviation (unqualified)

**Anomaly**:
A behavioral outlier raised by Layer 2 with an Anomaly Score. A *candidate* for
human review, explicitly not a Violation.
_Avoid_: violation, breach

**Case**:
The investigation record a human Auditor works on. Opened by a Violation, a
Conformance Deviation, or an Anomaly. Bundles the Hard Evidence and the AI Narrative,
and is resolved by a human.
_Avoid_: ticket, alert, incident, ca cảnh báo (use Case), process instance (different thing)

**SOP**:
The customer's documented standard operating procedure — the source material from
which Compliance Rules are authored and the context the Context Weaver retrieves.

### Evidence & roles

**Hard Evidence**:
The verdict-bearing, system-recorded facts behind a Case — transaction id, IP,
timestamps, before/after data diff, modification history. This is what the Auditor
signs the report on. Always kept separate from, and authoritative over, the AI Narrative.
_Avoid_: proof, data, logs (when meaning this specifically)

**Evidence Ledger**:
Bedrock's own append-only, encrypted store of Hard Evidence, living *outside* the
customer's ERP. Integrity is enforced by a hash-chain whose head is anchored externally
(periodic customer email + RFC-3161 timestamp), making tampering evident even against a
privileged Bedrock insider (Tier B). See ADR-0005, ADR-0009.
_Avoid_: audit log (that is Odoo's), history, journal

**AI Narrative**:
The LLM-written, human-readable summary of a Case produced by the Context Weaver. A
convenience for fast comprehension (~30 seconds vs hundreds of log lines). Never a
verdict, never signed on.
_Avoid_: report (unqualified), AI conclusion

**Auditor**:
The human user who reviews Cases, weighs the Hard Evidence, and makes the final
decision. The Judge in the system. The AI is only the Investigator.
_Avoid_: reviewer, user (when meaning this role)

**Human-in-the-loop**:
The invariant that every verdict and every consequential action requires a human
decision. The system's own authority never exceeds surfacing and explaining.

### Deliverables

**Audit Report**:
The immutable, exportable record produced as Cases are closed — Hard Evidence + the
Auditor's Attestation + timestamp, bound by a tamper-evidence hash. The v1 headline
deliverable. In v1 it carries an internal Attestation, *not* a public-CA Digital
Signature (deferred Enterprise add-on — see ROADMAP). See ADR-0008, ADR-0009.
_Avoid_: export, summary, signed report (it is attested, not CA-signed)

**Control Coverage**:
The always-on view of which Controls are active and their pass/fail status — evidence
that controls are working, not merely that violations are absent.
_Avoid_: dashboard (unqualified), report

**Attestation**:
The Auditor's recorded, identity-bound approval of a Case decision — an *internal*
assertion that the human reviewed the Hard Evidence and decided. Explicitly NOT a
chữ ký số: no public-CA certificate, no claim to statutory e-signature weight. The
honest v1 word for "signing". Scoped to the human's decision over the Hard Evidence —
the AI Narrative is bundled as context, never the thing attested.
_Avoid_: signature, ký số, sign-off (when implying legal weight)

**Digital Signature**:
A chữ ký số in the Vietnamese legal sense — a public-CA (Viettel / FPT / VNPT)
certificate applied via Remote/Cloud CA to an exported PDF Audit Report. A deferred
Enterprise add-on, not in v1. See ROADMAP.
_Avoid_: attestation (that is the weaker internal concept)

### Tenancy

**Organization**:
A customer tenant — the company that owns an Odoo instance being audited. Its data
lives in its own Postgres schema (ADR-0007). Owns one or more Connections.
_Avoid_: tenant (use Organization), account, company (unqualified)

**Connection**:
A configured link to one Odoo instance: its URL, a dedicated read-only credential, and
sync state. The unit Bedrock ingests from. An Organization may have several.
_Avoid_: integration, datasource, link

### Posture

**Detective**:
Finding Violations/Anomalies *after* documents are posted, by reading the ERP. The
v1 posture. Read-only — never writes to the ERP. See ADR-0001.
_Avoid_: monitoring (unqualified)

**Preventive**:
Blocking or altering a transaction *before* it completes. Bedrock itself never does
this (it stays read-only). In v1 preventive value is realized only via a customer-side
Actuator reacting to an Alert. See ADR-0001, ADR-0002.
_Avoid_: enforcement, automation (unqualified)

### Signalling

**Alert**:
The *precision channel*: a low-latency outbound signal Bedrock emits only when a finding
clears the promotion gate (see ADR-0010), delivered via Slack / Telegram / SMS / webhook
/ API. Optimized to be almost always real. An Alert points at a Case; it is not the Case
itself.
_Avoid_: notification (unqualified)

**Actuator**:
The customer-side agent — a human in the ERP, or the customer's own ERP automation —
that acts on an Alert (e.g. freezes the order). Lives on the customer's side of the
boundary. Bedrock never actuates. See ADR-0002.
_Avoid_: enforcer, bot

### Triage & prioritization

**Triage Queue**:
The *recall channel*: where every finding lands as a Case for review in the workbench
and periodic digest. Optimized to lose nothing, reviewed at leisure — the counterpart to
the precision-optimized Alert channel. See ADR-0010.
_Avoid_: inbox, backlog

**Severity**:
The deterministic criticality of a finding — rule criticality combined with money-at-risk.
Distinct from an Anomaly Score (which is statistical suspicion). One input to the Alert
promotion gate.
_Avoid_: priority, risk score (use Anomaly Score for the statistical one)

**Materiality Floor**:
The money-at-risk threshold below which a finding never promotes to an Alert (it still
opens a Case). Keeps trivial discrepancies out of the precision channel.
_Avoid_: threshold (unqualified)

**Suppression Rule**:
A known-good pattern marked as expected (e.g. a vendor whose payments legitimately
cluster at month-end), so matching findings do not promote to Alerts and may auto-close.
Fed by `dismissed` Case reasons. See ADR-0010.
_Avoid_: allowlist, mute, ignore rule
