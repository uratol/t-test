# Fabric-oriented refactoring: behavior changes

This describes the JSON, error-helper and runner changes in `install.sql`.
It separates compatibility changes from bug fixes.
Current deployment has nine scalar functions, seventeen framework procedures, two
discovery views and
seventeen basic test procedures. Basic verification expects 25 cases with default
registrations: fifteen static calls, four POWER vectors and six REPLICATE combinations.
Saved global registrations can change the executed count.
The SELECT-star sample now keeps all 50 contracts in 18 procedures: 30 schema vectors
in `select_star.test`, four schema/data vectors in `select_star.test_data` and 16 static
query-context tests. Both shared tests accept a label, expected columns and a star expression.
The schema test uses `FROM sys.objects s`, including qualified/correlated inputs.
The data test retains `WHERE object_id = OBJECT_ID('test.run')` and both assertions,
including value changes that do not change types. The correlated subquery keeps its filter.
The installer defines procedures only and retires the 34 replaced standalone procedures.
The run script resets the two shared tests' global registrations, defines the 34 vectors,
then calls `test.run`. Other objects and registrations
are preserved; registrations targeting retired names are not silently deleted.
The package is Fabric Warehouse-only. Its runner uses global storage
without session-context branches. Native packaging regressions cover repeatable upgrades,
schema match/mismatch behavior and global vector selection, not Fabric's SELECT-star syntax.
Each vector is declared with `EXEC test.vector`, not a direct registry-table insert.
`QUOTED_IDENTIFIER OFF` permits a double-quoted SQL argument list; apostrophes inside
argument values are doubled. `QUOTED_IDENTIFIER ON` is restored after registration.
The current installer and 49-group framework suite passed in a user-reported Fabric
Warehouse run after the scope-test compilation fix. The full local SQL Server release
check also passed, including all five mutation controls. This is not comprehensive
Fabric validation of every optional package or an instrumented coverage percentage.
An earlier user-reported Fabric run covered 43 groups, zero failures and five inherited
bugs; that historical result predates the current fixes.

## API naming cleanup

New code uses `test.is_equal`; `test.is_equals` remains its compatibility alias.
`test.assert_equals` now calls the canonical predicate directly. Schema assertion names
now distinguish a literal signature from two queries. Other assertion names, selectors
such as `@test_names`/`@test_schemas`, and `@log_proc_name` are unchanged.

| Before | Now |
| --- | --- |
| `test.is_float_equals` | `test.is_float_equal` |
| `test.reset` | `test.clear_registrations` |
| `test.set_scope` | `test.set_registration_scope` |
| `test.run @limit_failed` | `test.run @max_failures` |
| `test.run @before_callback` | `test.run @before_each_sql` |
| `test.vector @parameters` | `test.vector @arguments_sql` |
| `test.dimension @values` | `test.dimension @values_json` |
| `test.assert_schema @expected_schema` | `test.assert_schema_signature @expected_schema_signature` |
| `test.assert_schema_equals` | `test.assert_query_schemas_equal` |
| `test.get_query_schema @schema OUTPUT` | `test.get_query_schema @schema_signature OUTPUT` |
| `test.format_message @msg` | `test.format_message @message` |

Parameter positions, types, defaults and execution behavior are unchanged. Existing
positional argument lists still work with the current procedure/function name.
**Update named calls and retired module names in user code:** old parameter names are
not aliases, and the installer does not rewrite user modules. Only `is_equals` remains
as a compatibility name. Registry columns, including `test_vectors.parameters`, stay
unchanged.

Reinstallation replaces the shipped scope and schema self-tests with
`[tests].[test.set_registration_scope@fc_context]` and
`[tests].[test.assert_query_schemas_equal]`, migrates their saved global vector and
dimension keys without deduplication, and removes retired framework objects. It does
not clear user registrations. Existing caller-local session tables are not migrated;
re-register their old self-test keys on that connection if needed.

After upgrading the framework, rerun installed optional-package installers as well.
In particular, existing SELECT-star samples need their updated installer to replace
calls to the retired schema assertion name. New installations use the new names directly.

`api-tests.sql` checks renamed signatures, named calls, the equality alias, and combined
vector/dimension execution. Lifecycle tests cover root and optional-package upgrades,
duplicate registration preservation, repeated installation, and old/new-name removal.

## Assertion coverage and lifecycle hardening

The basic resultset self-test now independently rejects different values and
explicit NULL versus absent columns. The framework runner also includes the
previously omitted basic schema test: its positive group is now 33 procedures /
41 cases, within the same 49 scenario groups.

`assertion-tests.sql` adds 62 native SQL Server contracts for result data, row
ordering/multiplicity, NULL preservation, query validation/errors, schema
signatures, all type-formatting branches and metadata-probe cleanup.
`logger-tests.ps1` captures actual InfoMessage/PRINT payloads in 13 cases rather
than assuming success because the logger returned. AAA and independent comparisons
ensure these tests do not validate an assertion with itself.

`assert_schema_signature` now treats whitespace-only expected signatures like NULL/empty
input, with the same error 70001 and argument-specific diagnostic. Nonempty
signatures retain exact comparison. That hardening does not change public procedure
names, parameter positions, types or defaults; the separate naming cleanup is above.

Install/uninstall rejection now preserves native caller transactions and
XACT_ABORT settings even when an outer TRY/CATCH catches the guard error. SQL
Server raises the guard from a scoped `SET XACT_ABORT OFF` batch; Fabric skips
that unsupported SET. Uninstall uses error 50000 / severity 16, matching the
installer, instead of its former THROW 51090. Both scripts return before their
guarded work. Lifecycle regressions check XACT_ABORT OFF/ON, continued GO batches,
caught guards, repeated uninstall, custom objects/data and both registry multisets.

`run-regression-tests.ps1 -Server <instance> -MutationChecks` creates its own
fresh SQL Server database, runs every local regression group and removes that
database in `finally`. Five return-only mutations must be detected, with module
definitions verified before mutation testing and after restoration. These are
selected mutation controls, not a line/branch percentage.

The scalar FOR JSON restriction is now explicit in the API, README and static
data recipe. The resultset helper/catalog/data paths are not validated Warehouse
paths; native SQL Server success does not establish Fabric compatibility.

## SQL-script-only source and deployment

SSDT support is removed: the database project, solution, per-object SQL copies, and
post-deployment script are no longer maintained. `install.sql` is the authoritative
source for all framework modules and seventeen basic test procedures. Its 44 module
definitions matched the removed copies before deletion; schema, registry-table, and
POWER seed definitions are already included in the installer.

This removes project builds and DACPAC deployment, not SQL Server or Fabric support.
Execute the complete `install.sql` to install or upgrade. Optional package scripts,
uninstallation, test recipes, and existing optional-test upgrade refreshes are retained.
No runtime SQL behavior changes are introduced by removing the duplicate project.

## Test script organization

Framework regression scripts now live in `tests\regression`: framework coverage
installation/execution, vectors, dimensions, and the runner/installation PowerShell
harnesses. Domain examples live in `tests\samples\catalog`, `tests\samples\stdev`,
and `tests\samples\select-star`, each retaining its installer and paired runner.
Script basenames used elsewhere in these notes are unchanged.

The root `install.sql` remains authoritative and still includes basic verification;
SQL schemas, procedure names, registrations and execution behavior are unchanged.
PowerShell dependency paths and README links follow the new layout.

## Optional installation and execution separated

The four `install-*-tests.sql` packages now install without executing tests. Use their
matching `run-*-tests.sql` files afterward. The main `install.sql` is unchanged by this
split and still performs basic verification. Catalog/STDEV generators and all sixteen
framework self-test definitions are retained; no framework API behavior changes.

The framework installer persists six typed vectors and adds any missing four standard
POWER vectors in global storage, idempotently and without clearing other registrations.
It restores SQL Server's caller scope and installs no dimension domains. The paired runner
validates installation, reads those vectors, and retains all 49 scenario groups, including
the strict default 41-case positive run. Extra registrations for selected procedures can
fail that expectation; use a dedicated test database. Temporary observers and deliberately
failing runner fixtures belong to execution, not installation.

SELECT-star coverage uses 50 explicit-query oracles over existing system views,
without input-table DDL, input fixtures or transaction checks inside the tests.
30 schema cases are vectors; 16 query-context cases remain static.
Four REPLACE vectors additionally compare one stable catalog row through `test_data`.
The runner writes global vector registrations after a targeted reset. The four
CTAS tests are removed, and reinstallation drops their retired procedures. Materialized
table coverage is therefore no longer part of this package. Its paired runner selects
the `select_star` container through the standard framework runner.

Run-script selection is now discoverable rather than an exhaustive name manifest.
Catalog execution uses the tested-object `sys` schema, including its basic comparison;
STDEV execution selects `[tests].stdev@%`, including its basic and optional tests,
without building a name list with `STRING_AGG`. SELECT-star execution
selects all procedures in its dedicated schema and retains native reporting and non-error
RETURN behavior. Framework positive names
are declared once and reused for preflight/execution, avoiding unrelated or negative tests.
`runner-tests.ps1` adds SQL Server regression checks for these selection/reporting paths.

## Container schemas, LIKE selectors and review fixes

`test.run @test_schemas` selects the schemas containing test procedures; its exclusion
counterpart excludes those containers. Migrate old tested-object filters to
`@test_object_schemas` and `@exclude_test_object_schemas`. The new parameters are appended,
preserving the first seven positional slots. All schema lists accept `nvarchar(max)`,
avoiding the previous silent truncation after 256 characters.

Container filters are named `@test_schemas`/`@exclude_test_schemas`, replacing
`@schemas`/`@exclude_schemas`. Object filters also use plural `schemas`, matching their
list inputs. This naming-only change preserves parameter order, types and defaults;
old named arguments must be updated, with no compatibility aliases.

Names accept exact identifiers first, then SQL LIKE patterns. `[select_star].%` selects
every procedure in that literal schema, including schemas containing wildcard characters.
Included selectors with no matches and explicit schema lists with no procedures fail.
Overlapping selectors retain duplicate-error behavior. With no selectors, only `tests`
runs. Explicit schema selection treats every procedure in that schema as a test.

The new neutral `test.test_procedures` discovery view supports custom containers and
vector/dimension/reset registration. `test.test` preserves its original seven columns
and default `tests` scope. Framework procedures in `test` cannot receive registrations.
Obsolete `[test].` name-resolution fallbacks are removed.

The scalar numeric shortcut now rejects lossy fractional conversions instead of treating
distinct tiny/high-precision decimals as equal. Equivalent spellings beyond the supported
precision may compare unequal; use a typed comparison for arbitrary-precision decimals.
Basic and optional regression cases cover these boundaries.

The vector suite now snapshots/restores arbitrary global rows on success and failure,
rather than rejecting the optional framework package's six retained vectors. Restoration
checks compare byte-exact multisets, including duplicates. API and the three AAA recipe
pages now live in `docs`.

## Procedural assertions and reusable predicates

All `assert_*` APIs are now stored procedures, including `assert_error`.
Replace scalar calls such as `SET @r = test.assert_equals(...)` with
`EXEC test.assert_equals @message, @expected, @actual;`. Expressions passed to
procedures must first be computed into variables. Success emits no result grid.
Assertion failures use native error 70001 with the `Unit-test fail:` marker.
The runner still recognizes legacy `test.fail` conversion-error failures.

Value assertions reuse bit predicates: `is_equals`, `is_float_equal`, `is_null`
and `is_not_null`. `is_equals` delegates to existing `is_equal`, so both names
remain without duplicated equality logic. Invalid FLOAT tolerance returns 0 in
the predicate and raises a detailed assertion failure in the procedure.
`assert_error` has no `is_error` counterpart and still requires a genuine CATCH.

`fail_no_error` is also a procedure: replace scalar calls with
`EXEC test.fail_no_error;`. It raises native assertion error 70001 containing
`<<No error>>`; `assert_error` rejects this sentinel even when its filters match.

Installation drops old assertion functions before creating procedures and refreshes
shipped callers. Custom tests are retained, not rewritten; migrate their calls.
SQL Server and Fabric share these definitions. Existing Fabric global-only scope
rules are unchanged.

## Query-schema assertions

Adds `test.assert_query_schemas_equal @message, @expected_query, @actual_query` and
`test.assert_schema_signature @message, @expected_schema_signature, @actual_query`. They compare
ordered, case-sensitive column names and base SQL types, including length,
precision and scale, rather than returned data. Nullability and collations are
not compared.

Both reuse `test.get_query_schema`, which creates and cleans a uniquely named
view in schema `test` and reads catalog metadata without executing SELECT rows.
This shared SQL Server/Fabric path avoids scalar `FOR JSON` and `INSERT EXEC`.
It requires view-compatible queries, `CREATE VIEW` and permission to alter
schema `test`. CTEs are supported; ORDER BY requires TOP or OFFSET.

The standalone SELECT-star package uses these built-in assertions for 50 independent
query contracts in 18 procedures, mainly over `sys.objects`. Each compares an explicit
projection with a SELECT-star query; the reference is not generated. The original 42
cases are retained, with eight focused combination/alias/same-type additions. Four
REPLACE cases also compare values to catch mistakes invisible in metadata. Basic tests
are direct SELECTs over system views; WITH and subqueries are confined to the marked
edge-case section. There are no input
tables or CTAS tests; schema assertions themselves still create and clean metadata views.
The package-local schema helper is retired. Install the updated framework before
reinstalling the package. Installer, uninstaller and a framework self-test are synchronized.

## Vector and dimension parametrization

Adds `test.set_registration_scope`, `test.vector`, `test.dimension` and `test.clear_registrations`, whose optional
`@test_name` restricts cleanup to one discovered procedure. The runner preserves its
original seven positional slots and appends the two object-schema filters. Explicit vectors run first; dimension domains
produce a separate Cartesian product, not a product with the vectors.
An unset `ttest:vectors:scope` selects global `[test].[test_vectors]`; selecting
`session` uses caller-created `#test_vectors`. The setter is mutable and affects
only its connection. Registry columns are `procedure_name` and `parameters`.

Installation creates the global table if absent, using ordinary shared SQL
Server/Fabric DDL without a distribution clause. Existing compatible tables and
saved definitions are retained; session tables remain caller-provisioned.
Registration appends trusted SQL argument text unchanged;
duplicates execute separately. Missing tables warn and skip registration, while
run/reset silently skip the unavailable store. Native storage errors propagate.
Installation never alters or clears an existing registry. Uninstallation preserves
the global table and data.
Global reset deletes shared registrations explicitly; it does not change scope.

Before callbacks, the runner snapshots selected registrations through source-only
dynamic SQL. Vector definitions and metadata use scalar JSON; dimension values and
per-procedure generated cases use private temporary tables. Test-owned rollback
does not alter the captured definitions. Mixed/vector result grids use captured
metadata rather than joining live discovery. Parameterized counts and duration
aggregates use BIGINT. Dimension products are materialized before execution;
keep domains small because overflow checks are not a resource limit.

Start/completion logs identify each vector invocation and retain full EXEC text in
`@data`. Completion is recorded before honoring the failure limit; logger errors
abort rather than becoming test errors. With no selected vectors, static reporting
and logger behavior remain unchanged. Duplicate selection still executes the first
case in the second selection before raising error 50000. In a mixed/vector run this
framework error uses THROW to abort even without a caller CATCH, avoiding an
unrecorded invocation reported as successful; the legacy all-static behavior remains.
Vector result labels use the same name as static tests plus the original parameters
in parentheses, such as `power@vectors (-2,3,-8)`. Full EXEC text remains in internal
results and logs; it is not reconstructed from the display label.

Installer basic verification selects global scope on both engines. SQL Server
restores the original session-context value, including an unset key, on success
and failure; Fabric Warehouse supports global scope only. The installer inserts
only missing standard global POWER vectors; reinstallation
preserves existing rows and adds no duplicates. Verification uses saved global
vectors and temporarily replaces REPLICATE domains with six combinations, restoring
saved domains afterward. It drops the dimension table only if verification created it.
Test procedures do not register their own cases. The standalone `vector-tests.sql`
and `dimension-tests.sql` exercise 37 and 29 scenarios with disposable fixtures.
These mixed session/global diagnostic suites run only on SQL Server. The shared
installer and framework suite also passed the user-reported Fabric run using global scope.

## Basic verification and modular test packages

The shared `install.sql` defines and deploys seventeen basic procedures directly.
They retain the four original test names and add dedicated equality, NULL,
ordered/raw JSON, catalog-table, small STDEV, inline data-type and POWER vector checks.
Related error/fail helpers
are grouped in `test.throw`; all nine scalar functions are directly exercised.
This is functional basic coverage, not an instrumented coverage percentage.

The installer footer explicitly selects these seventeen procedures (25 cases with
default registrations). This intentionally
changes reinstallation from running every discovered test to running only basic
verification. Additional and user tests are retained. The basic naming check still
inspects all names, and a direct `EXEC test.run;` still executes all discovered tests.
The existing EngineEdition-specific execution wrapper and XACT_ABORT scope remain.

Optional installers define their packages; paired run scripts execute them.
`install-framework-coverage-tests.sql` adds sixteen procedures, and
`run-framework-coverage-tests.sql` executes 49 scenario groups, including 33
basic/positive procedures (41 cases). `install-compare-resultset-tests.sql`
adds twelve catalog tests, excluding the existing basic tables comparison;
`install-stdev-tests.sql` adds 27 numerical cases. Together with basic verification,
these provide 72 distinct procedures. The scripts replace the former
`full-coverage-test.sql`, `sys-objects-test.sql` and `stdev-test.sql` filenames.

## Review fixes and clearer tests

The static basic tests use inline values and separate Arrange, Act and Assert
where useful. Assertion-only tests omit artificial setup, JSON case matrices and
loops. Scenario tests use
framework assertions; independent comparisons and THROW remain available for
testing the framework itself. Catalog comparisons use ordered SELECT queries
captured with `FOR JSON PATH`. STDEV tests use equality/NULL assertions and an
explicit floating-point tolerance through `test.assert_float_equals`.

The new FLOAT assertion accepts message, expected value, actual value and
`@tolerance`. Its boundary is inclusive; zero requires exact equality.
Two NULLs match and one NULL fails. NULL/negative tolerances fail, even for equal
values. Failures use the normal assertion classification and show round-trip FLOAT
values and tolerance. Opposite-sign comparisons avoid subtraction overflow.
The twelfth basic test independently verifies these success/failure boundaries.

`test.assert_resultset_equals` compares two SELECT strings through dynamic
`FOR JSON PATH, INCLUDE_NULL_VALUES` captures and delegates to `test.assert_equals`.
It is a procedure, not a UDF, because functions cannot execute dynamic SQL.
It preserves row ordering, NULL properties and native query errors, and accepts an
optional trailing semicolon. It requires trusted, single-SELECT queries without
existing JSON clauses or CTEs; it does not enforce read-only access. The thirteenth
basic test compares ordered user-table metadata from `sys.objects` and `sys.tables`,
including typed columns and NULLs, using inline query strings.

`test.assert_error` combines optional expected number, LIKE message pattern and state
checks in one API, replacing `test.assert_error_like` and `test.assert_error_number`.
The former functions are removed, without aliases.
Reinstallation migrates the two shipped extended tests before dropping the legacy
functions. Custom calls must use `assert_error` with DEFAULT for omitted filters.

Checks run inside CATCH. NULL/DEFAULT skips each individual filter, but an active
genuine error is always required; the no-error sentinel is rejected. It uses
`ERROR_NUMBER()`, `ERROR_MESSAGE()` and `ERROR_STATE()`, not `@@ERROR`, and returns
int NULL on success. The fourteenth basic test covers
filter combinations, DEFAULT, matching/nonmatching patterns, escaped wildcards and
missing errors. FLOAT and THROW tests
also use it inside CATCH while retaining independent checks.

The missing-error sentinel is renamed from `test.error()` to
`test.fail_no_error()`. Its `<<No error>>` marker and rejection by error assertions
are unchanged. Installation refreshes the four affected optional procedures when
present, migrates the retained sentinel test and retires the old function name.
No compatibility alias remains; custom calls and helper-target test names must
use the new name.
Uninstall also removes both legacy sentinel objects when present.

SYS catalog tests compare all 12 shared columns plus schema name, including NULLs,
integer IDs, dates and bit flags. INFORMATION_SCHEMA tests include equivalent
catalog, kind, parent and date fields. The new inline-row test covers scalar
types, FLOAT/REAL, Unicode, long text and spatial values without persisted fixtures.
Geometry/geography use WKT plus SRID because `FOR JSON` cannot serialize them
directly. JSON/XML typed values are intentionally excluded.

Error-number assertions reject the no-error sentinel even when 245 is expected;
real conversion errors still match. Both error-number and pattern assertions now
fail through `test.fail`, so mismatched expectations count as assertion failures,
not unexpected application errors. Runner parsing requires the native conversion
prefix and failure marker and handles truncated diagnostics without losing the
original exception. Literal percent signs cannot break logger output truncation.

Failed callbacks roll back transactions they opened and rethrow the original
exception. Coverage preflight gates every registration batch, rejects existing
fixture/helper names and cleans up only objects created by the current run.
Rejected runs preserve caller transactions, including pending writes. The retained
catalog self-test also removes its fixtures after unexpected validator errors.

Filter scenarios verify executed identities and multiplicities, not just counts.
NULL-pattern rejection checks both the error number and diagnostic, so unrelated
conversion errors cannot pass. These changes pass local SQL Server checks, and the
updated shared framework suite also passed a user-reported Fabric Warehouse run.

## Current JSON comparison: ordered result sets

The public names are `test.assert_resultset_equals` and `test.is_json_equal`.
`test.assert_error` names its LIKE filter `@expected_message_pattern`.
The installer migrates shipped tests and removes the former `assert_query_equals`
and `is_equal_openjson` APIs without compatibility aliases. Custom callers must
use the new names; `test.assert_float_equals` is unchanged.

`test.is_equal` now calls `test.is_json_equal` after its unchanged text/NULL
and numeric-string shortcuts. Two `OPENJSON` rowsets and an `OUTER APPLY` expose
integer row indexes, property names, raw values and JSON types. A `FULL OUTER JOIN`
matches row indexes and property names and checks for missing or different fields.
There are no normalization buffers, checksums, grouped row matching or date/number
conversion inside JSON comparison.

Row order matters; property order does not. JSON numeric spellings such as `1`,
`1.0` and `1e0` differ, as do different date-string formats. Values use SQL
comparison rules, including collation and padding. The intended input is a shallow
result set with unique column names of at most 128 characters. Nested values are
compared as raw JSON text, not recursively interpreted.

`test.normalize_json` is removed from the installer.
Reinstallation drops that function and the former numeric/prototype helpers.
Existing `[tests].[test.is_equal@fc_values]` is refreshed in place. If obsolete
normalizer coverage exists, it is replaced by
`[tests].[test.is_json_equal@fc_json]`; the three owned legacy normalization
procedures are dropped. The replacement procedure has a new object ID, so grants
on the removed procedures do not transfer. Unrelated tests are retained, and fresh
installs do not create optional coverage. Experimental scripts and backup files
have been removed.

`install.sql` is the sole installer, without `WITH INLINE = AUTO`.
The byte-identical `install-fabric.sql` duplicate was removed.
The shared execution wrapper below remains unchanged. The user reported that the
ordered catalog comparisons pass on Fabric Warehouse; the final cleanup/upgrade
DDL still needs a Fabric run.

## Test result table

The first `test.run` result table now returns `test`, `duration, s`, `status` and
`failure_reason`. This intentionally replaces the public `is_success`, `is_failed`
and `is_error` integer columns. Consumers of the old output schema must be updated.

`status` is `PASS` or `FAIL`. Both assertion failures and unexpected exceptions
produce `FAIL`; `failure_reason` distinguishes them with `Assertion failed: ...`
or `Unexpected exception: ...` and includes the original diagnostic message.
Successful tests have a NULL reason, including tests that catch and verify their
expected exceptions. Internal classification, summary counts, failure limits
and the duration-by-schema result table remain unchanged.

## Shared runner execution scope

The `test.run` definition in `install.sql` omits `SET XACT_ABORT`.
The shared installer footer calls `test.run` directly on EngineEdition 11. Other
editions execute `SET XACT_ABORT OFF; EXEC test.run;` in one `sp_executesql` batch.
The runner, tests, and their child procedures inherit OFF on SQL Server, while
the caller's setting is restored when the dynamic batch exits. Fabric executes
no `SET XACT_ABORT` statement.

This changes direct native calls outside the installer wrapper: `EXEC test.run`
now inherits the caller's setting instead of forcing OFF. Callers requiring the
former error-continuation behavior must use the same wrapper or set OFF themselves.
Installation still executes its tests; no scripts are split by this change.

## Historical refactoring

The JSON-normalization descriptions below record retired implementations, not the
current equality contract. Ordered/raw comparison above supersedes their numeric,
date, binary-encoding and order-insensitivity guarantees.

- `normalize_json` replaces its table-variable/identity buffer with ordered
  `STRING_AGG` over hexadecimal binary records, then converts the result back to
  binary. The initial buffer-only refactoring preserved the legacy encoding and
  number normalization. The subsequent bug corrections below deliberately replace
  those details while retaining recursive handling, array order-insensitive
  comparison, date normalization and duplicate retention.
- `test.run` replaces its cursor and table-variable results with scalar JSON arrays.
  Selection filters, callbacks, failure classification, rollback, failure limits,
  grouping and result-column types are preserved, subject to the changes below.
- Duplicate selections are not silently deduplicated. Each occurrence executes its
  callback and test before duplicate-result rejection. Rejected results are not
  appended; the first result remains. Continuation and caller `TRY/CATCH` behavior
  follow the original runner. Execution order remains unspecified.

## Intentional compatibility changes

| Condition | Original error | Current error | Preserved severity/state |
|---|---|---|---|
| NULL test name in results | 515, NOT NULL constraint | 50000, `Test name cannot be NULL` | 16 / 2 |
| Duplicate test result | 2627, PRIMARY KEY constraint | 50000, `Duplicate test result` | 14 / 1 |

JSON arrays have no table constraints, so explicit validation uses `RAISERROR`.
This preserves statement-level continuation without prematurely terminating the
runner. Error numbers and validation message text intentionally differ.
`test.throw` and the final failure summary still use 70000.

Errors originating inside the runner can report different line numbers because
its source moved. Errors inside unchanged test procedures retain their test-line
locations. Exact diagnostic text is therefore not a byte-for-byte compatibility
guarantee.

## Bug fix: incomplete JSON normalization under SET ROWCOUNT

**The original behavior was a bug:** a nonzero `SET ROWCOUNT` limited insertion
into the normalization buffer. Later JSON elements were ignored, allowing
different documents to compare equal and assertions to pass incorrectly.

With `SET ROWCOUNT 1`, the original normalizer considered `[1,2,3]` and `[1,9,10]`
equal because only their first sorted elements were retained. The new normalizer
processes the complete documents and correctly reports them as different:

```sql
SET ROWCOUNT 1;
SELECT test.is_equal(N'[1,2,3]', N'[1,9,10]'); -- Now returns 0; previously 1.
SET ROWCOUNT 0;
```

This is an accepted behavior correction, not an equivalence-preserving refactor.
It does not reset the caller's ROWCOUNT setting or remove report row limits.
Tests relying on the old false-positive comparison must be corrected.

## Inherited JSON bugs: reproduced before correction

**Historical normalization behavior:** this section and the normalization rows in
the five-bug correction table below describe an intermediate, now-retired normalizer.
They are not the current equality contract. Today's `is_json_equal` compares ordered
rows and raw values/types: the numeric-notation and reordered-array examples below
return 0, not 1. Embedded NUL values are compared through OPENJSON rather than the
old binary encoding. See [current JSON behavior](README.md#json-result-comparison).

The following were confirmed in the original implementation and the initial
buffer-only refactoring, not introduced by Fabric support. All were reproduced
under all three tested collations with `ROWCOUNT 0`. They are now fixed as described
in the correction section below.

### False-positive equality with embedded NUL

Key/value records use unescaped zero-byte separators without length prefixes.
An embedded NUL can make different key/value boundaries produce identical binary
records. Different JSON objects can therefore pass an equality assertion:

```sql
SELECT test.is_equal(N'{"a":"\u0000b"}', N'{"a\u0000":"b"}');
-- Original / initial refactoring: 1. Corrected implementation: 0.
```

### False-negative equality for equivalent numeric notation

Numeric normalization attempts `DECIMAL(30,20)` conversion and otherwise keeps
the original text. Exponent-form numbers can fall back to their spelling instead
of being normalized to the same numeric value:

```sql
SELECT test.is_equal(N'[1,1.0,1e0]', N'[1.000,1e+0,1]');
-- Original / initial refactoring: 0. Corrected implementation: 1.
```

### False-negative equality when sort keys tie

Normalization sorts object keys or normalized array values using SQL string
comparison. Different strings can have equal sort keys because of collation
rules or trailing-space padding, including under binary collations. Without a
binary tie-breaker, permuting those records can change their concatenated bytes.
Equivalent objects or order-insensitive arrays can then compare as different:

```sql
SELECT test.is_equal(N'[0,"a","A","a "]', N'[0,"a ","A","a"]');
-- Original / initial refactoring: 0. Corrected implementation: 1.
```

Exhaustive four-element permutations confirmed this for arrays and object
properties. The affected permutations depend on collation and equal-key ordering;
the original implementation does not guarantee a canonical order for ties.

Matching original/current binary output is not proof of correct JSON equality:
the comparison can preserve a bug. These cases are tracked separately from
regressions and from the accepted ROWCOUNT bug fix.

## Additional inherited error-helper bugs found by coverage tests

These two bugs were independently reproduced using the original Git HEAD function
definitions and the initial refactoring. The first coverage suite documented
rather than fixed them; the subsequent correction now rejects both cases.

### Numeric-only raw error message does not throw

`test.throw_error` raises an error by casting the message to `int`. Numeric-only
messages convert successfully, so the helper can return instead of throwing:

```sql
SELECT test.throw_error(N'123'); -- Previously returned N'123'; now raises error 245.
```

`test.fail` is not affected by this particular input: it prefixes the message with
`Unit-test fail:`, making the conversion fail as intended.

### Historical NULL-pattern bug and the unified error assertion

The retired `test.assert_error_like` originally accepted NULL because `NOT LIKE NULL`
evaluates to UNKNOWN. It was corrected before the API was consolidated.
`test.assert_error` intentionally treats a NULL pattern as an omitted filter;
other supplied filters still apply, and a genuine caught error remains required:

```sql
BEGIN TRY
    THROW 51011, 'Expected exception', 1;
END TRY
BEGIN CATCH
    EXEC test.assert_error N'Number-only check', 51011, DEFAULT, DEFAULT;
END CATCH;
```

Numeric-only raw errors and omitted message filters have `PASS`/`FAIL` regressions in
`run-framework-coverage-tests.sql`,
not optional `KNOWN BUG` probes or Fabric regressions.

## Corrections to all five inherited bugs

| Bug | Corrected behavior |
|---|---|
| Embedded NUL record collision | Binary key/value lengths and a type tag separate each record unambiguously. |
| Equivalent exponent notation | The embedded numeric algorithm produces an exact signed coefficient/exponent representation. |
| Collation/padding sort ties | Complete binary records are sorted, independently of string collation and padding. |
| Numeric-only raw error message | Messages convertible to `int`, including empty/whitespace strings, receive `Error: ` before the forced conversion. |
| NULL error pattern | The retired helper rejected NULL. The unified `assert_error` skips a NULL filter but still requires a genuine error and checks other supplied filters. |

The initial `normalize_number` scalar helper handled arbitrarily long decimal
coefficients and exponent digits within SQL string limits, without `FLOAT`,
`DECIMAL` rounding or expanding large powers of ten. Its algorithm now lives
directly in `normalize_json`, and the redundant standalone helper is retired.

The numeric correction also removes the legacy JSON-number precision loss from
`DECIMAL(30,20)` and `FORMAT(..., 'g18')`: different high-precision or tiny nonzero
numbers must not compare equal after rounding. This is a coupled bug correction.
The existing non-JSON numeric-string comparison in `is_equal` remains unchanged.

**Normalized binary output intentionally changes.** It is an opaque comparison
representation, not a stable storage format. Regenerate externally stored or cached
normalizations; do not compare the old and new encodings. Array/object distinction,
JSON type tags, duplicate retention and existing date normalization remain intact.

Non-numeric `throw_error` messages keep their existing native conversion behavior
and diagnostics. Numeric messages now throw error 245 with `Error: ` in the text;
NULL still returns NULL. The `Unit-test fail:` and `<<No error>>` markers are
unchanged, so runner failure/error classification is preserved.

The intermediate normalized implementation passed these five regressions.
Historical local runs under binary and case-insensitive
UTF-8 collations return `PASSED`, 43 groups, zero failures and zero known bugs.
The initial native SQL Server checks also passed the four original bundled tests;
the local harness checks numeric error lines instead of Fabric's required `N/A`.
Those historical results alone do not verify the latest ordered/raw implementation
on Fabric; the current 49-group suite has since passed a user-reported Warehouse run.
For current verification, rerun the complete `install.sql`, then
`install-framework-coverage-tests.sql`, followed by the entire
`run-framework-coverage-tests.sql` in one session.

## Intermediate refactoring regressions corrected

These were bugs in intermediate implementations, not bugs in the original code:

- Temporary buffers lost during rollback: replaced with scalar JSON variables.
- Duplicate validation logged twice: removed the redundant logging path.
- `THROW` stopped execution after the second occurrence in `A|A|A`: replaced
  validation throws with statement-level `RAISERROR`, preserving original
  continuation, callback counts and failure-limit handling.

## Verification and limitations

Differential execution against the original covered three SQL Server collations,
including binary and case-insensitive UTF-8. Checks included transactions,
duplicates, caller error handling, filters, catalog changes during callbacks,
Unicode/control characters, large JSON buffers and recursion boundaries.

At `ROWCOUNT 0`, tested normalizations matched byte-for-byte. Nonzero-ROWCOUNT
differences are recorded as the accepted bug fix above, not as passing equivalence
checks. Source and installer definitions match.

Performance and memory usage are not equivalent: JSON buffers are repeatedly
parsed/copied, and hexadecimal aggregation needs temporary text storage. Removing
cursors and table variables alone does not establish full Fabric compatibility.

## Shared installer for SQL Server and Fabric

`install.sql` supports SQL Server 2022+ and Fabric Warehouse. Its platform
adaptations address the reported Fabric installation errors; shared bug fixes
and naming-validator cleanup are maintained in this same installer:

| Fabric restriction | Installer adaptation | Behavior difference |
|---|---|---|
| Procedure `EXECUTE AS` is unsupported | The installer omits `EXECUTE AS 'dbo'` from `test.log` | Logging runs as the caller; object names depend on the caller's metadata visibility. |
| `SET XACT_ABORT` is unsupported | The runner omits it; the footer sets OFF only in a native dynamic batch | Fabric retains its own transaction behavior; direct runner calls inherit the caller's setting. |
| `@@PROCID` is unsupported | Runner and throw self-test IDs use `OBJECT_ID` | Names are explicit; renaming these procedures requires updating the lookup literals. |
| `SQL_VARIANT_PROPERTY` is unsupported | Formatting uses explicit caller-side date/hex conversion | Automatic typed date/binary formatting is removed; see the shared formatting change below. |
| `ERROR_LINE()` is unsupported | The runner skips line lookup for EngineEdition 11; other editions use dynamic SQL | Fabric displays `Line: N/A`; SQL Server retains the actual error line without a static unsupported call. |
| Nested `FOR JSON` is unsupported | The discovery self-test builds JSON using `JSON_OBJECT` and `STRING_AGG` | The compared properties and omission of NULL fields are retained. |
| Scalar UDF inlining restrictions | Use shallow OPENJSON rowsets and a join; omit `WITH INLINE = AUTO` | Ordered/raw comparison replaces normalization; no procedural parser remains. |

These are platform adaptations, not bug fixes or a claim of complete behavioral
equivalence. The earlier approved JSON-buffer changes and known equality bugs
still apply. Caller-context logging does not grant permissions; the installer and
runner need suitable schema/object permissions and metadata visibility.

The logger in the shared installer omits `EXECUTE AS 'dbo'` on both platforms.
This intentionally removes impersonation; it grants no extra
permissions. Logging still prints messages, but procedure names can be absent
when the caller cannot see the corresponding object's metadata. Existing SQL
Server installations must rerun the installer to apply the new context.

The runner checks `SERVERPROPERTY('EngineEdition')`, not the product version.
Edition 11 covers Fabric Warehouse and Azure Synapse serverless; it skips the
unsupported line lookup. Other editions execute `ERROR_LINE()` inside a constant
`sp_executesql` string with an integer OUTPUT parameter while still in CATCH.
The statement text has no caller-supplied SQL. A missing line remains NULL and is
displayed as `N/A`; the variable is reset for each caught error.

The runner and throw self-test use explicit `OBJECT_ID` lookups on both platforms.
Dynamic `@@PROCID` would not reliably identify the enclosing procedure, so it is
not used. Renaming either procedure requires updating its lookup literal. Local
checks can exercise both branches but do not establish actual Fabric behavior.

All retained scalar functions use one `RETURN`; a single return alone
does not establish inlineability. Function bodies are maintained in `install.sql`.
`is_equal` guards arguments passed to `is_json_equal`, so
inlining cannot send invalid JSON from a skipped branch into JSON parsing.
The installer has no `INLINE = AUTO` clause; the former procedural normalizer
and its standalone number helper are removed.

The discovery self-test in the installer compares a constant expected JSON value
with actual JSON built using
`JSON_OBJECT` with `ABSENT ON NULL`, aggregated as `nvarchar(max)`. This removes
that test's dependency on `FOR JSON PATH`. The target is SQL Server 2022 or later
and Fabric Warehouse, not SQL Server 2019. The original installer already used
SQL Server 2022 syntax, including `IS DISTINCT FROM` and the `ISJSON` type constraint.

### Shared naming-validator cleanup

The legacy SQL Server validator accepted `DDL trigger.<name>` test targets when
the name existed in `sys.triggers`, even though `OBJECT_ID` did not resolve the
schema-qualified target. Fabric has no DDL triggers and already omitted that branch.
The exemption is removed from the naming-validator body in `install.sql`,
including its precomputed failure text.

Conceptual tests can now use `object@action` without a schema or physical target.
Discovery preserves the concept and action with NULL target-schema metadata, and the
validator skips their object-existence checks. Both name parts must be nonempty;
bare unqualified names remain invalid. Dots after `@` are part of the action, not a
target schema. Schema-qualified targets retain the existing `OBJECT_ID` check and
private-schema grouping. No default schema or new schema-filter group is introduced.

`install-stdev-tests.sql` creates `stdev@...` procedures instead of `math.stdev@...`.
For each registered case it removes only the corresponding legacy procedure after
creating its replacement. Rerunning the file migrates the original 27 tests;
unrelated procedures are retained. The framework installer does not rename user tests.

This intentionally removes special acceptance of DDL-trigger names on SQL Server;
it does not create, drop or disable database triggers. The general object-existence
check remains enabled, so logical targets such as `math.stdev` still need explicit
test selection or exclusion of the naming validator for an unfiltered suite.

The earlier Fabric formatter compared style 0 and style 1 conversions as binary
strings to recognize typed dates/binary without parsing text. It retained date
styles 101/114 and binary style 1. Local differential checks covered 648 cases
across all four parameter positions and three languages, including numeric,
date/time, binary, text, truncation and conversion-error cases. Those checks
describe the former implementation, not the new formatting contract or Fabric's
conversion behavior.

### Shared explicit message formatting

The formatter in the shared installer omits date/binary type detection.
Callers must explicitly convert dates/timestamps with style 126 for ISO text and
binary values with style 1 for hex text. This intentionally replaces automatic
date styles 101/114 and automatic binary formatting. Raw typed inputs remain
accepted through `sql_variant` but receive ordinary text conversion; existing
`test.format_message` and `test.log` callers relying on special formatting must
be updated. Bundled tests and the coverage suite use explicit conversions.

NULL handling, unassigned parameters, numeric substitution, substitution order
and the 4,000-character parameter limit remain unchanged. Date-like and hex-like
text stays text. No time zone is inferred or converted, and no `Z` is appended;
callers requiring UTC must supply a value known to be UTC. The README includes
matching formatter and logger examples.

The installer also refreshes `[tests].[test.format_message@fc_parameters]` if
that coverage procedure already exists, before running installation tests. This
updates the legacy automatic-formatting expectations to the full current coverage
definition without dropping the procedure. Fresh installations do not create this
optional coverage test, and unrelated user tests are not changed. The strict
naming validator remains enabled and can still reject logical `math.stdev` targets.

Missing schemas are created conditionally. Framework modules and bundled tests use
`CREATE OR ALTER`, allowing retries after a partial installation without deleting
user tests. Completion is printed only after checking all required objects and
running the seventeen basic procedures (25 cases with default registrations).
Existing user tests are retained, not executed.
Deployment is not atomic; inspect every batch error even if older objects exist.

The reported Fabric errors confirm five unsupported constructs above, including
the later `SQL_VARIANT_PROPERTY` and `ERROR_LINE()` installation failures.
The previous installer and extended framework coverage suite subsequently passed
in a user-reported Fabric Warehouse run, including recursive JSON handling, tested
UDF calling contexts, DDL rollback and error continuation. The updated bug-correction
version still requires execution there; local SQL Server checks do not establish
Fabric guarantees or untested distributed UDF calling contexts.

## Extended functional coverage suite

`install-framework-coverage-tests.sql` adds sixteen positive procedures without
changing the framework implementation. Assertions, error helpers, equality,
logging, throwing and discovery have dedicated extended tests. Its paired
`run-framework-coverage-tests.sql` runs
these with all seventeen basic procedures (33 procedures, 41 cases), then checks runner behavior and
corrected regressions in 49 scenario groups.

Scope coverage checks exact mutable `SESSION_CONTEXT` values and rejects invalid
inputs without changing the last valid scope. Six typed vectors cover positional
and reordered named arguments, numeric limits, decimals, scientific notation, bit,
Unicode and quoted text, date/datetime2, binary, NULL and DEFAULT. These vectors are
installed globally; execution reads them without replacement and restores SQL Server's
caller scope. Fabric retains global-only scope. The factory vectors survive verification.

Expected failures are verified independently with native T-SQL checks rather than
assuming an assertion succeeded because it did not throw. Temporary observers
check execution/callback counts, logging context and summary classification.
The final duplicate probe intentionally has no caller `TRY/CATCH`; all batches
must execute in the same session. Completeness checks reject skipped groups.

Only owned fixture/helper procedures and temporary tables are removed. Positive
tests remain available for subsequent `test.run` calls. Logging's PRINT/InfoMessage
text is exercised but cannot be captured and asserted by this SQL-only suite.
No instrumented line/branch coverage percentage is claimed.
