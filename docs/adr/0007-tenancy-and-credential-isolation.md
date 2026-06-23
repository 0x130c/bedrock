# Schema-per-tenant isolation + read-only least-privilege ERP credentials

Bedrock stores customers' financial evidence outside their ERP (ADR-0005), so isolation
strength is both a real security property and a sales argument for a compliance buyer.

- **Schema-per-tenant.** Each Organization's data lives in its own Postgres schema
  (Ash `:context` multitenancy), single database. Strong isolation story
  ("your evidence is in its own schema, not a shared table") with manageable ops.
  Rejected: row-level `tenant_id` (weak isolation narrative for a compliance product)
  and database-per-tenant (ops overkill for v1). "Start row-level, migrate later" is
  rejected outright — tenancy migration is among the most painful, so we pay the cost
  up front.
- **Read-only, least-privilege ERP credentials.** Each Connection requires a dedicated
  *read-only* Odoo account/API key, stored encrypted (`ash_cloak`). Even a full Bedrock
  compromise cannot write to a customer's ERP — enforcing ADR-0001's read-only posture
  at the credential layer, not just by convention.

## Consequences

- Every migration runs per-schema; tenant provisioning creates a schema. Accepted as
  the cost of the isolation guarantee.
- The read-only credential makes the deferred Preventive/write-back module (ADR-0001) a
  deliberate, separately-credentialed future step — it cannot happen by accident.
