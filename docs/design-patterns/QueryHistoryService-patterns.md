# QueryHistoryService — Design Pattern Analysis

## Pattern chosen: Service Layer + Audit-Log (write-behind, fire-and-forget)

`QueryHistoryService` is a stateless service that owns every read and write of
`SOQL_Query_History__c`. It is the only place in the codebase that inserts or deletes a
history record, and it is invoked from `SoqlWhispererController` _after_ a query has already
run. The logging entry point is deliberately fire-and-forget: it returns `void` and never
throws, so the caller's control flow is untouched whether the write succeeds or not.

## Patterns evaluated

| Pattern                          | Fit          | Reason rejected / accepted                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Service Layer + Audit Log        | **Selected** | Stateless, static, single responsibility: "persist and retrieve run metadata." Keeping it out of `QueryService` is what makes the read-only guarantee against queried org data structural rather than documentary.                                                                                                                                                               |
| Decorator around `QueryService`  | Rejected     | A `LoggingQueryService` wrapping `QueryService.runQuery` is the textbook fit and was seriously considered. Rejected because Apex has no DI container: the LWC calls a named `@AuraEnabled` method, so the "decorator" would have to be the controller method anyway. It would add an interface and a class for zero substitutability.                                            |
| Observer / Platform Events       | Rejected     | Publishing a `Query_Run__e` and logging in a trigger would fully decouple logging from the query path and survive rollback. But it adds an event definition, a trigger and a handler, makes history eventually-consistent (the panel would not show the run the user just made), and consumes event publishing limits — all for a feature whose logging is already non-blocking. |
| Queueable (async write)          | Rejected     | Async logging would remove the insert from the synchronous transaction, but a Queueable cannot be enqueued after a callout in every configuration, adds a job per query run, and would still be invisible to the immediate refresh. The synchronous insert is one DML row.                                                                                                       |
| Unit of Work                     | Rejected     | fflib-style UoW earns its keep when many objects are written in one transaction with dependency ordering. Here exactly one record of one type is written. Pure overhead.                                                                                                                                                                                                         |
| Repository / Selector (separate) | Rejected     | Splitting `getRecent`/`clearMine` into a `QueryHistorySelector` would leave a two-method service. The class is small enough that the query and the DML belong together; the limit clamp lives beside the query it protects.                                                                                                                                                      |
| Command (retry queue)            | Rejected     | Retrying a failed history write would mean persisting the failed command somewhere — i.e. exactly the write that just failed. History is disposable diagnostics, not a financial ledger; a dropped row is acceptable.                                                                                                                                                            |

## Why Service Layer + Audit Log

The class exists to answer one question — "what did this user run, and how did it go?" — and
to do so without ever becoming a precondition of the thing it observes. Service Layer gives a
stateless, testable seam that `SoqlWhispererController` can call in one line; the audit-log
framing is what dictates the unusual contract (`void`, never throws, silently degrades).

### The DML boundary — why this class exists at all

This project is read-only against **queried org data**. Phase 4 is the first feature to write
anything, so the boundary is drawn in class structure, not in comments:

- `QueryService` performs `validate()` then `Database.queryWithBinds(..., AccessLevel.USER_MODE)`
  and contains **zero** DML. It is not modified by this phase beyond removing a stray
  `@AuraEnabled` annotation (see below).
- All history DML lives here, targets `SOQL_Query_History__c` and nothing else.
- `SoqlWhispererController.runQuery` calls `QueryService.runQuery(soql)` first, then calls
  `logRun(...)`. `QueryService` never calls this class — the dependency arrow points one way.

That arrangement makes the guarantee reviewable by grepping a single file: if `QueryService`
contains no `insert`/`update`/`delete`/`upsert`, the executor cannot mutate org data, full stop.

A related structural fix shipped with this phase: `QueryService.runQuery` previously carried
`@AuraEnabled`, which meant any LWC could call the executor directly and bypass history
logging entirely. That annotation is removed. The controller wrapper is now the only
LWC-reachable path to execution, so "every run is logged" is enforced by the API surface
rather than by convention.

### The never-throw logging contract

`logRun` wraps everything — record construction, truncation and the insert — in a single
try/catch that swallows. The realistic failure is mundane: an admin deploys the code but
forgets to assign the `SOQL_Whisperer_User` permission set, so `AccessLevel.USER_MODE` rejects
the insert for lack of Create. Without the swallow, every user of the tool would see their
query fail with a confusing permissions error about an object they have never heard of, even
though their query itself succeeded perfectly.

The controller adds a second `try/catch` around the call. That is redundant while `logRun`
honours its contract, and it is kept on purpose: it means a future regression inside
`QueryHistoryService` still cannot turn logging into a blocker for query results.

Limits of the guarantee, stated honestly:

- `LimitException` (the uncatchable kind — CPU timeout, too many DML rows) cannot be caught by
  any Apex code, here or anywhere. If the transaction is already over a governor limit the
  whole request dies regardless of this class.
- A failed log is silent. Nothing is written to the debug log (prohibited in production code)
  and nothing is surfaced to the user. The cost of the never-throw contract is that a
  systematically broken permission set looks like "history is just empty." That is documented
  as the expected first thing to check when history does not populate.

### `USER_MODE` + OWD Private instead of manual owner filters

Both new objects are OWD Private with no sharing rules. The class is `with sharing`, reads use
`WITH USER_MODE` and writes use `Database.insert(..., AccessLevel.USER_MODE)`. Consequently
`getRecent` has **no** `WHERE OwnerId = :UserInfo.getUserId()` clause: the platform already
restricts the result to records the running user owns. Adding the filter would duplicate the
sharing model in application code, and worse, it would mask a genuine misconfiguration — if
OWD were ever loosened to Public Read, a hand-rolled filter would keep the UI looking correct
while the underlying data was exposed to every user and to every other tool in the org.

`clearMine()` is the deliberate exception and **does** filter on `OwnerId`. It is a bulk,
irreversible delete, and a system administrator has View All / Modify All Data — without the
filter, an admin clicking a button labelled "Clear my history" would delete every user's
history org-wide. The filter is a blast-radius guard, not a substitute for sharing. The
asymmetry with `getRecent` is intentional and worth the inconsistency.

### Governor handling for a high-volume object

History gets one row per query run, so it is the only high-volume object in the project.

- **Reads are never unbounded.** `getRecent(Integer limitSize)` clamps the caller-supplied
  value to `[1, 200]` (null → 25) before it reaches the query. The LWC's "Show more" button
  walks 25 → 50 → 100 → 200, but the clamp is server-side precisely so the ceiling does not
  depend on a client behaving itself.
- **Ordering is `CreatedDate DESC, Name DESC`.** The auto-number name increases with insert
  order, so it is a deterministic tie-breaker for rows created in the same second — otherwise
  ordering assertions in tests are flaky.
- **`clearMine()` is capped at `LIMIT 10000`**, matching the DML row limit, so a single clear
  can never blow the limit. A user with more than 10,000 rows clears in repeated passes.
- **One DML statement per run.** Logging adds exactly one insert to the query transaction —
  no loop, no bulk path, nothing that scales with result size.
- **No trim-on-insert.** Deleting old rows during the synchronous query path was considered
  and rejected: it doubles the DML on the user's critical path to manage storage. Retention is
  manual (`clearMine`) for now; a scheduled batch purge is a Phase 5 candidate and the absence
  of one is a documented limitation, not an oversight.

### Two objects, not one with a `Type__c` flag

History and saved queries share three fields, which is a real temptation to merge. They were
kept separate because their lifecycles are opposites: history is high-volume, machine-created
and purgeable; saved queries are low-volume, user-named and permanent. The decisive argument
is blast radius — a retention purge scoped to a dedicated history object **cannot** delete a
user's saved work, no matter how wrong its `WHERE` clause is. With one object plus a type
flag, a single missing predicate destroys saved queries irrecoverably. Three duplicated fields
is a cheap price for making that class of bug structurally impossible.

## Trade-offs

| Pro                                                                                               | Con                                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `QueryService` stays provably DML-free; the read-only claim is checkable by reading one file.     | The controller now has a responsibility (ordering execution and logging) that a decorator would have encapsulated.                                                                                                                                        |
| Logging can never break a query run.                                                              | Logging failures are invisible. A missing permission set presents as "history is empty," not as an error.                                                                                                                                                 |
| Server-side clamp means a compromised or buggy client cannot force an unbounded query.            | The client cannot request more than 200 rows even legitimately; deep history requires clearing or a future purge/paging feature.                                                                                                                          |
| Synchronous insert means the run appears in the history panel immediately.                        | It costs one DML statement inside the user's query transaction (vs. an async or platform-event design that would cost none).                                                                                                                              |
| No manual owner filters on reads, so the sharing model is the single source of truth.             | Correctness depends on OWD staying Private. If someone loosens it, history becomes cross-visible — mitigated only by the two-user `System.runAs` isolation test.                                                                                          |
| `USER_MODE` enforcement is real, not decorative — verified by a real scratch-org test failure.    | Every Apex test that touches this object must run inside `System.runAs(<SOQL_Whisperer_User user>)`, because Metadata-API-deployed fields grant FLS to nobody by default (2026-09-11 fix, see `docs/2026-09-10-phase-4-export-history-saved-queries.md`). |
| Defensive truncation means an over-length input degrades one field instead of failing the insert. | Truncation is silent: a 6,000-character query is stored clipped at 5,000, and re-running it from history would run a different (broken) query. Acceptable — no generated query is near that.                                                              |

## Apex-specific constraints that influenced this decision

- **No dependency injection.** The LWC binds to a named `@AuraEnabled` method, so a Decorator
  pattern cannot be swapped in at runtime; the controller method _is_ the composition root.
  This is the main reason the textbook decorator was rejected.
- **Governor limits.** 150 DML statements / 10,000 DML rows per transaction, and 50,000 rows
  per SOQL query. The clamp, the `LIMIT 10000` on clear, and the single-row insert all exist
  to keep history a rounding error against these.
- **`AccessLevel.USER_MODE` enforces object and field permissions**, which means the feature is
  inert without the `SOQL_Whisperer_User` permission set — a deliberate fail-closed posture,
  and the exact scenario the never-throw contract is designed to survive.
- **`LimitException` is uncatchable**, so "never throws" is precisely bounded: it means "never
  throws a catchable exception," and that is the strongest guarantee Apex permits.
- **Restricted picklist.** `Status__c` accepts only `Success` / `Error`; `normalizeStatus`
  maps anything else to null rather than letting a bad caller value fail the whole insert.
- **No `@future`.** Per project convention; and async logging was rejected on its merits above.
- **Rollback semantics — a real limitation of the chosen design.** The history insert shares
  the user's query transaction. On the **success** path the controller returns normally, the
  transaction commits, and the row persists. On the **error** path the controller logs and then
  rethrows so the LWC's error handling is unchanged — but an exception escaping an
  `@AuraEnabled` method rolls the whole transaction back, **including the error history row**.
  So in a deployed org, failed runs will typically not appear in history even though the code
  attempts to log them.

  This is inherent to synchronous same-transaction logging; no try/catch arrangement fixes it,
  because Apex offers no explicit commit. The only mechanisms that survive rollback are a
  Platform Event published with `publishBehavior = PublishImmediately` (or an equivalent
  out-of-band write). Both were out of Phase 4 scope, and the chosen trade — keep the LWC's
  exception contract identical, accept that error rows are best-effort — was made knowingly.
  Note the asymmetry when reading the tests: an Apex test that catches the exception itself
  never hits the transaction boundary, so the error row **is** visible to the test. The test
  proves `logRun` is invoked on failure; it does not prove the row survives in production.
  Persisting failed runs reliably is a Phase 5 candidate alongside the scheduled purge.
