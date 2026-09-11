# SavedQueryService — Design Pattern Analysis

## Pattern chosen: Service Layer over a per-user Repository (upsert-by-natural-key)

`SavedQueryService` is a stateless service that owns every read and write of
`SOQL_Saved_Query__c`. It exposes three operations — `saveQuery`, `listMine`,
`deleteSavedQuery` — and nothing else touches the object. Save is an upsert against a
_natural key_ the platform cannot enforce for us (`Name` + owner), so the match-then-branch
logic lives here rather than in a database constraint.

## Patterns evaluated

| Pattern                                | Fit          | Reason rejected / accepted                                                                                                                                                                                                                                                                                                       |
| -------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Service Layer (+ Repository inline)    | **Selected** | Stateless CRUD over exactly one object with one small business rule (overwrite-by-name). Service and selector responsibilities are small enough that splitting them would produce two anaemic classes.                                                                                                                           |
| Repository / Selector (separate class) | Rejected     | A `SavedQuerySelector` would hold two queries, both of which exist only to serve the three methods here. The split earns its keep when multiple services share the SOQL; nothing else in the project reads this object.                                                                                                          |
| Platform `upsert` on an External Id    | Rejected     | The natural key is `Name` + `OwnerId`, and an External Id field can only be built from a single field. Synthesising a composite key field (e.g. `OwnerId + ':' + Name`) would need a formula or a trigger to maintain, and would leak the owner id into a user-visible field. Explicit match-then-branch is clearer and cheaper. |
| Unique constraint on `Name`            | Rejected     | Uniqueness in Salesforce is **org-wide**, not per-owner. Making `Name` unique would mean one user saving "My accounts" blocks every other user in the org from that name — an absurd failure mode for a per-user tool. Dedupe therefore has to happen in Apex.                                                                   |
| Command (undoable save/delete)         | Rejected     | An undo stack would need its own persistence and a UI affordance nobody asked for. Delete is already low-stakes: a saved query is one line of text the user can re-save.                                                                                                                                                         |
| Strategy (pluggable sharing policy)    | Rejected     | Speculative. There is exactly one sharing policy today (owner-only). If team-shared saved queries are ever added it will be via an `Is_Shared__c` flag plus a criteria-based sharing rule — a declarative change, not an Apex strategy.                                                                                          |
| Factory                                | Rejected     | No creation abstraction needed; the class builds one concrete SObject.                                                                                                                                                                                                                                                           |

## Why Service Layer over a per-user Repository

The class has one responsibility — durable storage of a user's named queries — and one rule
worth a decision (what "save" means when the name already exists). Service Layer gives a
stateless, `with sharing` seam the controller can call in one line, with all the SOQL and DML
for this object in a single auditable file.

### The DML boundary — why DML lives here and never in `QueryService`

The project rule is read-only against **queried org data**, not "no DML ever". Phase 4 draws
that line structurally:

- `QueryService` runs `validate()` then `Database.queryWithBinds(..., AccessLevel.USER_MODE)`
  and contains **zero** DML. This phase does not modify it apart from removing a stray
  `@AuraEnabled` annotation from `runQuery`, so that the only LWC-reachable execution path is
  the controller wrapper.
- Every write in Phase 4 lives in `SavedQueryService` (this class, `SOQL_Saved_Query__c` only)
  or `QueryHistoryService` (`SOQL_Query_History__c` only). Nothing else, ever.
- This class never executes, validates, or even parses user SOQL. It treats the query as an
  opaque string it is storing on the user's behalf. Execution stays exclusively in
  `QueryService`, behind its two safety layers.

The result is that "this tool cannot mutate your org data" is verifiable by grepping two files
for DML keywords rather than by trusting prose.

### Never-throw logging is _not_ this class's contract — and that is deliberate

`QueryHistoryService.logRun` must never throw, because history is a side effect of something
the user actually asked for; failing their query to report a failed log would be absurd. The
inverse is true here. "Save this query" _is_ the user's request, so a failure must be loud:
`saveQuery` and `deleteSavedQuery` throw `AuraHandledException` with actionable text for blank
input or a missing record, and any platform DML failure propagates. Silently swallowing a
failed save would be the worst possible outcome — the user would believe their work was
stored.

One Apex-specific wrinkle: `AuraHandledException` does not surface its constructor message to
the client unless `setMessage()` is also called; without that the LWC only ever sees
"Script-thrown exception". The private `clientError()` helper does both, which is why the
user-facing validation messages actually reach the toolbar.

### `USER_MODE` + OWD Private instead of manual owner filters

`SOQL_Saved_Query__c` is OWD Private (internal and external) with no sharing rules. The class
is `with sharing`, every query uses `WITH USER_MODE`, and every DML call uses
`Database.insert/update/delete(..., AccessLevel.USER_MODE)`. That combination means:

- `listMine()` needs **no** `OwnerId` filter — the platform already returns only the running
  user's records. Duplicating the sharing rule in a `WHERE` clause would make the UI look
  correct even if OWD were accidentally loosened, hiding the misconfiguration instead of
  exposing it. The two-user `System.runAs` isolation test is what proves the model holds.
- `deleteSavedQuery(Id)` does no owner check either. It selects the record in user mode first;
  for another user's record that select simply returns nothing and the caller gets "no longer
  exists, or you do not have access to it." The record is unreachable without a single line of
  bespoke authorisation code.
- `saveQuery` **does** filter on `OwnerId`, and for a different reason: it is not a security
  check, it is the natural-key lookup. The overwrite rule is specifically "a saved query _I_
  own with this name", and admins with View All Data would otherwise match another user's
  record and update it.

The sharing model matters more here than for history because the stored SOQL **text** can
itself carry PHI in `WHERE`-clause literals (`WHERE MRN__c = '00481923'`). Sharing a saved
query would not let a recipient read data they are not entitled to — execution is still user
mode — but the search-criteria leak is real, so the object defaults closed.

### Governor handling

Saved queries are deliberate and low-volume — the opposite of history — but the limits are
still respected explicitly rather than by assumption:

- `listMine()` is capped at `LIMIT 200`. No query in this class is unbounded.
- `saveQuery` does exactly one `SELECT ... LIMIT 1` plus one single-row insert or update: two
  queries and one DML statement, independent of how many saved queries the user has.
- `deleteSavedQuery` is one `SELECT ... LIMIT 1` plus one single-row delete.
- No SOQL or DML inside any loop; there is no loop.
- Text values are truncated to their field lengths (Name 80, SOQL 5,000, Natural Language and
  Object Scope 1,000) before DML, so an over-length input cannot raise
  `STRING_TOO_LONG` on a save the user expected to succeed.

### Two objects, not one with a `Type__c` flag

History and saved queries share three fields, but merging them was rejected. Their lifecycles
are opposites — history is high-volume, machine-created, auto-numbered and purgeable; saved
queries are low-volume, user-named and permanent. The decisive argument is blast radius: a
retention purge scoped to a dedicated history object **cannot** delete a user's saved work,
however wrong its `WHERE` clause. With one object plus a type flag, one missing predicate in a
future purge irrecoverably destroys saved queries. Three duplicated fields buys structural
immunity to that entire class of bug. The permission model differs too — history grants
Read/Create/Delete/Edit (Edit was added post-merge on 2026-09-11 only because the platform
requires it before granting Delete, which `clearMine()` needs under `USER_MODE`; immutability
is enforced by convention — no update method exists against `SOQL_Query_History__c` anywhere in
Apex or the LWC — not by FLS), saved queries are full CRUD used as designed — which one object
could not cleanly express.

## Trade-offs

| Pro                                                                                                                   | Con                                                                                                                                                                                          |
| --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Overwrite-by-name gives users an intuitive "save over it" without a duplicate-name mess.                              | Overwrite is silent — a user who reuses a name loses the previous query with no confirmation. Mitigated only by field-level help on the name input.                                          |
| No org-wide unique constraint, so users never collide on names with each other.                                       | Uniqueness is enforced in Apex, so two truly simultaneous saves of the same name could both insert. Harmless in practice (a per-user tool with a manual button) but not database-guaranteed. |
| Isolation comes from the sharing model, not hand-written checks — less code, fewer places to get authorisation wrong. | Correctness depends on OWD staying Private. A future admin loosening it silently makes saved SOQL cross-visible; only the isolation test catches that.                                       |
| Failures are loud, so the user always knows whether their query was stored.                                           | Opposite contract to `QueryHistoryService`; the two sibling services behave differently on error and that asymmetry must be understood before editing either.                                |
| The service stores an opaque string and never parses or runs it.                                                      | A saved query can therefore go stale — a field or object it references may be deleted later. It fails at run time, not at save time.                                                         |
| Truncation prevents avoidable DML failures.                                                                           | Truncation is silent; a pathologically long query is stored clipped and would run differently if reloaded.                                                                                   |

## Apex-specific constraints that influenced this decision

- **Org-wide uniqueness.** Salesforce unique fields are scoped to the org, not the owner,
  which is the single constraint that forced dedupe into Apex. This is the whole reason
  `saveQuery` is match-then-branch rather than a declarative `upsert`.
- **External Id upsert is single-field**, so the composite natural key (`Name` + `OwnerId`)
  cannot be expressed as a platform upsert without synthesising and maintaining a key field.
- **`AccessLevel.USER_MODE` enforces object and field permissions**, so the feature is inert
  until the `SOQL_Whisperer_User` permission set is assigned — fail-closed by design.
- **`AuraHandledException` message handling** requires `setMessage()` in addition to the
  constructor argument for the text to reach the LWC; see `clientError()`.
- **`with sharing` + OWD Private** is the entire isolation mechanism. No `without sharing`
  anywhere in this project, and no system-mode query or DML was introduced.
- **Governor limits** (100 SOQL / 150 DML statements per transaction) are never approached:
  every operation is a constant two-or-fewer statements with explicit `LIMIT` clauses.
- **No `@future`**, no triggers, no scheduled jobs on these objects, per project convention
  and Phase 4 scope.
