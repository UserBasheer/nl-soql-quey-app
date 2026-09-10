# SchemaService — Design Pattern Analysis

## Pattern chosen: Repository / Selector (describe-backed, read-only)

`SchemaService` encapsulates all native schema-introspection (`Schema.getGlobalDescribe`,
per-type and per-field `getDescribe`) behind a small, typed API
(`listObjects`, `describeObject`, `buildSchemaContext`). Callers — the
`SoqlWhispererController` and, transitively, the LWC — never touch the describe layer
directly. This is the Repository/Selector pattern applied to metadata rather than records:
it is the single place that knows _how_ schema is read and _which_ schema is exposed.

## Patterns evaluated

| Pattern               | Fit          | Reason rejected / accepted                                                                                                                                                                                                              |
| --------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repository / Selector | **Selected** | Centralizes schema reads + the permission/noise filter in one auditable place; returns typed DTOs (`ObjectInfo`, `FieldInfo`). The exclusion + sort policy lives behind one method.                                                     |
| Service Layer         | Partial      | The class is service-shaped (stateless, static), but its responsibility is _retrieval of schema_, not business orchestration. That orchestration lives in `SoqlWhispererController`. Selector is the more precise label.                |
| Strategy              | Rejected     | The exclusion rules (custom setting / deprecated-hidden / system suffixes) are a single fixed policy, not swappable algorithms. Introducing a strategy interface would be speculative complexity for one policy.                        |
| Factory               | Rejected     | No object-creation abstraction needed; DTOs are trivial value objects. (The translation _provider_ uses a Factory — `TranslationProviderFactory` — but that is a separate concern.)                                                     |
| Specification         | Considered   | The filter chain (permission gate, then noise gate) is specification-like. Kept inline as private predicates (`isSystemObject`) rather than a formal Specification object — clearer for a fixed, small ruleset and easier to unit-test. |

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
- Exclude system-sibling objects for the noise suffixes `Share`, `History`, `Feed`,
  `ChangeEvent`, `Tag` (system/setup noise no user would ground a business query on).
- Sort the result by label (case-insensitive, API name as tie-breaker) via a
  `Comparator<ObjectInfo>` for a stable, user-friendly picker order.
- **No hard cap** — accessible business objects are never silently truncated. If a large
  org needs a limit, it must be surfaced in UX, not hidden here.

Standard objects and `__c` custom objects are retained. `ObjectInfo`, `describeObject`,
and `buildSchemaContext` are unchanged.

## Fix — noise matching must be describe-informed, not string-only

The original Phase 3 implementation stored the suffixes in their double-underscore form
(`__Share`, `__History`, …) and matched with a plain `endsWith`. That form only ever exists
for siblings of **custom** parents (`MyObject__c` → `MyObject__Share`). Standard parents
produce siblings with **no** underscore — `AccountShare`, `CaseHistory`, `OpportunityFeed`,
`AccountChangeEvent` — so the entire standard-object half of the noise set passed straight
through the filter and reached the picker. A scratch-org validation run caught this.

Dropping to a bare `endsWith('share')` for everything would over-match: any legitimately
named object ending in one of those words would silently disappear from the picker, which
is a worse failure (a user cannot query what they cannot see) than showing a stray share
table. So the predicate is now **describe-informed** rather than purely lexical — the
`isCustom()` result already available on the `DescribeSObjectResult` inside the
`listObjects()` loop selects which form to match:

| Object                        | Form matched       | Example                                                                                                    |
| ----------------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------- |
| Custom (`isCustom() == true`) | `__` + suffix only | `MyObject__Share` excluded; a custom object is never bare-matched                                          |
| Standard                      | bare suffix        | `AccountShare`, `CaseHistory` excluded                                                                     |
| Any                           | `__` + suffix      | always noise — the double-underscore form is a reserved platform pattern, so it is checked unconditionally |

Two guards keep this narrow: the `__`-form check runs for every object (so a custom-parent
change event is caught no matter how its describe reports `isCustom()`), and every match
requires the API name to be strictly longer than the suffix, so an object named exactly
`Tag` or `Feed` is not hidden by a sibling rule that does not apply to it.

This is still narrowing-only: no permission logic changed, the
`isQueryable() && isAccessible()` gate is untouched, and `buildSchemaContext`'s egress
shape is unaffected. Only the private `isSystemObject` predicate and the constant it reads
changed; the public contract is identical.

## Trade-offs

| Pro                                                                                                                               | Con                                                                                                                                                                                                                                                                                                                         |
| --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One auditable place for the "what objects are visible" decision.                                                                  | Exclusion policy is hardcoded; an org wanting a configurable allow/deny list would need Custom Metadata (out of current scope).                                                                                                                                                                                             |
| Narrowing-only design means the change cannot widen access or leak objects.                                                       | Suffix-based exclusion is still heuristic — a standard object legitimately ending in `Share`/`History`/`Feed`/`Tag` would be hidden. Accepted: on the standard-object side these are effectively reserved sibling patterns, and the `isCustom()` branch keeps custom business objects out of the bare-suffix rule entirely. |
| `isCustom()` is already on the `DescribeSObjectResult` the loop holds, so the correct matching form costs no extra describe call. | The predicate now needs describe context, not just a name — it can no longer be reasoned about (or unit-tested) as a pure string function.                                                                                                                                                                                  |
| Label sort gives deterministic, testable ordering.                                                                                | Sorting + filtering still pays a full `getGlobalDescribe()` + per-type describe pass; cost is unchanged from before (governor-bounded, acceptable).                                                                                                                                                                         |

## Apex-specific constraints that influenced this decision

- **Read-only / no DML.** The class performs only describe reads. No DML anywhere; nothing
  here touches `QueryService.validate()` or `USER_MODE` execution.
- **`with sharing` + describe FLS.** Class is `with sharing`; `isQueryable()`,
  `isAccessible()` (objects) and `isAccessible()` (fields in `describeObject`) reflect the
  running user's effective object/FLS visibility. The Phase 3 filter only _narrows_ this —
  it can never expose an object the user could not already query.
- **Data egress.** The only path to the external translation provider is
  `buildSchemaContext`, whose shape (object + field API names + types — no record data) is
  unchanged. Letting users pick more objects can grow the schema-context _size_ (a prompt-
  budget concern), but never changes the _kind_ of data sent. No PHI or record data is ever
  included.
- **Governor limits.** A single `getGlobalDescribe()` plus per-type describe is bounded by
  the describe-limit; filtering/sorting in-memory adds no SOQL/DML. The describe traversal
  cost is identical to the prior implementation.
