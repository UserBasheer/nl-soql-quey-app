# SchemaService — Design Pattern Analysis

## Pattern chosen: Repository / Selector (describe-backed, read-only)

`SchemaService` encapsulates all native schema-introspection (`Schema.getGlobalDescribe`,
per-type and per-field `getDescribe`) behind a small, typed API
(`listObjects`, `describeObject`, `buildSchemaContext`). Callers — the
`SoqlWhispererController` and, transitively, the LWC — never touch the describe layer
directly. This is the Repository/Selector pattern applied to metadata rather than records:
it is the single place that knows *how* schema is read and *which* schema is exposed.

## Patterns evaluated

| Pattern | Fit | Reason rejected / accepted |
|---------|-----|---------------------------|
| Repository / Selector | **Selected** | Centralizes schema reads + the permission/noise filter in one auditable place; returns typed DTOs (`ObjectInfo`, `FieldInfo`). The exclusion + sort policy lives behind one method. |
| Service Layer | Partial | The class is service-shaped (stateless, static), but its responsibility is *retrieval of schema*, not business orchestration. That orchestration lives in `SoqlWhispererController`. Selector is the more precise label. |
| Strategy | Rejected | The exclusion rules (custom setting / deprecated-hidden / system suffixes) are a single fixed policy, not swappable algorithms. Introducing a strategy interface would be speculative complexity for one policy. |
| Factory | Rejected | No object-creation abstraction needed; DTOs are trivial value objects. (The translation *provider* uses a Factory — `TranslationProviderFactory` — but that is a separate concern.) |
| Specification | Considered | The filter chain (permission gate, then noise gate) is specification-like. Kept inline as private predicates (`isSystemObject`) rather than a formal Specification object — clearer for a fixed, small ruleset and easier to unit-test. |

## Why Repository / Selector

The class's single responsibility is "given the running user, what schema is visible and
relevant, in a model-friendly shape." Keeping describe access and the
visibility/noise policy in one `with sharing` class makes the security and data-egress
surface easy to audit: there is exactly one method that decides which object names can
ever reach a picker, and one method (`buildSchemaContext`) that decides what metadata
reaches the translation provider.

## Phase 3 change — `listObjects()` scope refinement

`listObjects()` previously returned every `isQueryable() && isAccessible()` object. That
permission gate is unchanged. Added on top of it (narrowing only, never widening):

- Exclude `isCustomSetting()` and `isDeprecatedAndHidden()` objects.
- Exclude API names ending in `__Share`, `__History`, `__Feed`, `__ChangeEvent`, `__Tag`
  (system/setup noise no user would ground a business query on).
- Sort the result by label (case-insensitive, API name as tie-breaker) via a
  `Comparator<ObjectInfo>` for a stable, user-friendly picker order.
- **No hard cap** — accessible business objects are never silently truncated. If a large
  org needs a limit, it must be surfaced in UX, not hidden here.

Standard objects and `__c` custom objects are retained. `ObjectInfo`, `describeObject`,
and `buildSchemaContext` are unchanged.

## Trade-offs

| Pro | Con |
|-----|-----|
| One auditable place for the "what objects are visible" decision. | Exclusion policy is hardcoded; an org wanting a configurable allow/deny list would need Custom Metadata (out of current scope). |
| Narrowing-only design means the change cannot widen access or leak objects. | Suffix-based exclusion is heuristic — a (rare) legitimately-named `*__Tag` business object would be hidden. Accepted: these suffixes are reserved system patterns. |
| Label sort gives deterministic, testable ordering. | Sorting + filtering still pays a full `getGlobalDescribe()` + per-type describe pass; cost is unchanged from before (governor-bounded, acceptable). |

## Apex-specific constraints that influenced this decision

- **Read-only / no DML.** The class performs only describe reads. No DML anywhere; nothing
  here touches `QueryService.validate()` or `USER_MODE` execution.
- **`with sharing` + describe FLS.** Class is `with sharing`; `isQueryable()`,
  `isAccessible()` (objects) and `isAccessible()` (fields in `describeObject`) reflect the
  running user's effective object/FLS visibility. The Phase 3 filter only *narrows* this —
  it can never expose an object the user could not already query.
- **Data egress.** The only path to the external translation provider is
  `buildSchemaContext`, whose shape (object + field API names + types — no record data) is
  unchanged. Letting users pick more objects can grow the schema-context *size* (a prompt-
  budget concern), but never changes the *kind* of data sent. No PHI or record data is ever
  included.
- **Governor limits.** A single `getGlobalDescribe()` plus per-type describe is bounded by
  the describe-limit; filtering/sorting in-memory adds no SOQL/DML. The describe traversal
  cost is identical to the prior implementation.
