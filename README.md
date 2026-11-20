# T-TEST

A **lightweight, pure‑T‑SQL unit‑testing framework** for SQL Server. Drop‑in installation, zero external dependencies, CI‑friendly output.

For signatures and examples, see the [API reference](docs/api.md).

For complete Arrange / Act / Assert recipes, see
[static tests](docs/static-test-recipes.md), [data-driven vector tests](docs/data-test-recipes.md),
and [dimension tests](docs/dimension-test-recipes.md).

For the Fabric-oriented refactoring, see [Behavior changes](CHANGES.md), including
intentional compatibility changes, bug fixes and verification limits.
The [API naming migration](CHANGES.md#api-naming-cleanup) lists renamed procedures,
functions and named arguments. Parameter order, types and defaults remain unchanged.

## Source of truth and deployment

`install.sql` is the authoritative source for framework objects, basic tests, and
standard POWER registrations. Edit these definitions directly in that script;
there is no separate database project or generated installer to synchronize.

Install or upgrade by executing the complete script on SQL Server 2022+ or Fabric
Warehouse. SSDT project builds and DACPAC deployment are no longer supported.
Optional tests are maintained in their package scripts listed below; the installer
retains its existing compatibility refreshes for already-installed optional tests.
Those refreshes must stay consistent with their packages when changing those tests.
When upgrading renamed APIs, rerun installed optional-package installers too; existing
SELECT-star samples need the updated package to call `test.assert_query_schemas_equal`.

---

## ✨ Features

* **100 % T‑SQL** – no CLR, PowerShell or external test runner required.
* **Self‑discovering tests**: every procedure in the `tests` schema is a test.
* **Rich assertions**:

  * smart equality (ordered recordsets, `NULL`, numbers, JSON)
  * exception pattern matching
  * null / not‑null shortcuts
* **Caller-managed isolation** - use a dedicated test database and explicit transaction
  cleanup where appropriate; the runner does not automatically isolate each test.
* **Minimal footprint** – assertion procedures and predicate functions in `test`, plus a view + runner.
* **CI‑ready** – `test.run` prints a concise summary and raises on failure, giving your pipeline a non‑zero exit code.

---

## 🚀 Quick start

### 1. Install

Simply execute the included **install.sql** script in the database you want to test:

```sql
:r install.sql
```

The script will:

1. **Create two schemas** that hold the framework internals and your tests (see table below).
2. Register and run **17 basic test procedures (25 cases with default registrations)**
   at the end, including four POWER vectors and six REPLICATE dimension combinations.
   All 25 cases are expected to pass; saved global registrations can change the count.
   Existing additional and user tests are retained, but are not executed by installation.

| Schema  | Purpose                                                |
| ------- | ------------------------------------------------------ |
| `test`  | framework internal objects: runner, assertions, logger |
| `tests` | **your** test procedures live here                     |

### Fabric Warehouse installation

Use **[install.sql](install.sql)** for both SQL Server 2022+ and Fabric Warehouse.
In the Fabric SQL query editor, paste the entire script and run it,
including the `GO` batch separators. Use an account with permission to create
schemas, tables, views, functions and procedures.

On SQL Server, installation, registration, reset and test runs require `ROWCOUNT 0`.
If changed, issue `SET ROWCOUNT 0` directly in the calling batch beforehand.
Do not issue `SET ROWCOUNT` on Fabric Warehouse; it is unsupported.

The shared installer creates missing schemas and uses `CREATE OR ALTER` for
framework objects and bundled tests. It can repair a partial installation without
deleting existing user tests. It runs only the seventeen basic test procedures at the end,
and prints completion only after the required objects exist and the
test run returns successfully. Inspect all errors in Messages; installation is
not atomic, and a later batch can run after an earlier batch fails.

Run installation outside a transaction and stop on errors (for example, `sqlcmd -b`).
The verification batch repeats the transaction guard before changing fixtures, preserving
caller transactions even when a client continues after a preflight error.
These guards raise error 50000 and return without rolling back caller data. On SQL Server,
the raise runs in a scoped dynamic batch with `XACT_ABORT OFF`, preserving the caller's
setting and committable transaction even when the error is caught by an outer TRY/CATCH.
The Fabric branch does not issue `SET XACT_ABORT`.

[uninstall.sql](uninstall.sql) has the same transaction guard. Run it outside a transaction
to remove framework modules and the 72 shipped basic/framework/catalog/STDEV procedures.
Schemas, custom tests, registry tables and their data are retained; cleanup is not atomic.
Custom tests need the framework reinstalled before execution.

Basic verification uses global scope on both engines. Fabric Warehouse (EngineEdition 11)
does not support session scope; selecting it raises an error without reading session context.
On SQL Server, verification restores the caller's original scope on success or failure.
Installation creates `[test].[test_vectors]` if missing. It never alters an existing
registry table or clears saved definitions. It inserts only missing standard POWER
vectors; repeated installation does not duplicate them. Uninstallation preserves the table
and data. Verification uses saved global vectors. It temporarily installs six REPLICATE dimension
combinations, restores that procedure's saved domains, and drops the dimension table only if verification created it.

The installer runs `test.log` as the caller, without `dbo` impersonation.
Procedure names in logs depend on the caller's metadata visibility.
The runner definition in `install.sql` omits `SET XACT_ABORT`. The installer footer
calls the runner directly on Fabric (EngineEdition 11); elsewhere it executes `SET XACT_ABORT OFF`
and `EXEC test.run` together inside one dynamic batch. Tests and their child
procedures inherit that setting, and the caller's setting is restored afterward.
A direct `EXEC test.run` outside this wrapper inherits the caller's setting instead.
The installer replaces `@@PROCID`
with explicit object-name lookups and avoid nested `FOR JSON` in discovery tests.
There is one installer, without `WITH INLINE = AUTO`.
JSON equality uses `OPENJSON` and a join, not normalization.
Use assertion procedures, such as `EXEC test.assert_equals N'Result', 1, @actual;`.
Compute expressions or scalar queries into variables before passing them to `EXEC`.

The formatter omits date/binary type detection on both platforms.
Convert dates and binary values to text explicitly, as shown below. The runner
checks `SERVERPROPERTY('EngineEdition')`: edition 11 skips line lookup and shows
`Line: N/A`. Other editions call `ERROR_LINE()` only through parameterized dynamic
SQL inside CATCH, keeping the unsupported function out of Fabric's static code.

See [Behavior changes](CHANGES.md#shared-installer-for-sql-server-and-fabric) for
permission, transaction and validation limitations.
The previous installer and extended suite passed in a user-reported Fabric Warehouse
run. The latest review fixes still require execution there.
Rerun the complete `install.sql`, then the complete coverage file below.
Current native release checks run on SQL Server, not Fabric. In particular,
the scalar `FOR JSON` data-capture paths have a documented Warehouse restriction;
see [Comparing two SELECT statements](#comparing-two-select-statements).

### Basic verification and additional packages

The basic procedure definitions live directly in `install.sql`.
Fifteen use static cases; POWER uses four registered
vectors and REPLICATE uses six temporary dimension combinations:

| Basic test | Checks |
|---|---|
| `test.test` | Discovery and metadata for temporary test procedures. |
| `test.test@name_convention` | Naming and referenced-object validation. |
| `test.format_message` | Substitutions, explicit formatting and a logger smoke check. |
| `test.throw` | THROW, raw errors, fail/no-error helpers and error-number/pattern assertions. |
| `test.assert_equals` | Equal values/NULLs and a caught mismatch. |
| `test.assert_float_equals` | Inclusive absolute tolerance, NULLs, invalid tolerance and extreme FLOATs. |
| `test.assert_resultset_equals` | Compare ordered catalog results; independently reject different values and NULL versus absent columns. |
| `test.assert_query_schemas_equal` | Compare query schemas, explicit signatures, CTEs and caught schema mismatches. |
| `test.assert_error` | Optional error number, LIKE message pattern and state; absent/sentinel errors are rejected. |
| `test.assert_not_null` | Ordinary/empty bytes and a caught NULL rejection. |
| `test.assert_null` | NULL and a caught non-NULL rejection. |
| `test.is_equal` | Scalar shortcuts and direct ordered/raw OPENJSON comparisons. |
| `sys.objects@tables` | All 12 shared catalog columns plus schema name, including NULLs. |
| `stdev@basic` | Known sample deviation and one/zero-value NULL boundaries. |
| `data_types@basic` | Independently defined rows of numeric, temporal, text, binary, GUID, NULL and spatial values. |
| `power@vectors` | POWER with vectors `2,3,8`, `3,2,9`, `5,0,1` and `-2,3,-8`, saved globally at installation. |
| `replicate@dimensions` | REPLICATE byte lengths for two counts and three strings; verification temporarily registers six combinations. |

These are functional self-tests, not exclusively integration tests. They exercise
all nine scalar functions, assertion procedures, logger/throw helpers, discovery and the runner;
this is not measured line/branch coverage. Expected scalar-UDF failures run outside
explicit transactions. Most basic tests print two short description lines;
`replicate@dimensions` does not.

Basic tests use inline values and separate Arrange, Act and Assert where useful.
Assertion-only examples omit unnecessary setup, JSON case matrices and loops.
Scenario tests use framework assertions: catalog queries capture ordered results
with `SET @json = (SELECT ... FOR JSON PATH)`, and STDEV tests use `assert_null`
or `assert_float_equals` with an absolute tolerance. Framework self-tests use independent comparisons
and `THROW` so a broken assertion cannot validate itself. All assertions use `EXEC`,
return no result grid on success, and raise error 70001 on failure. The `is_*`
predicates return bit 1/0 without asserting.

SYS catalog pairs compare every shared column, including integer IDs, datetime
timestamps and bit flags; none has a shared FLOAT column. INFORMATION_SCHEMA pairs
also compare equivalent catalog, kind, parent and date fields where available.
The inline-row test supplies FLOAT/REAL coverage alongside other scalar types,
Unicode and long strings. Its geometry/geography variables are compared through
`STAsText()` and SRID because `FOR JSON` cannot serialize spatial types directly.
JSON/XML values are excluded; JSON is only the comparison transport.

Test scripts are grouped by purpose:

```text
tests\
  regression\          Framework, runner, installation, vector and dimension checks
  samples\
    catalog\           Ordered result comparisons over system catalogs
    stdev\             Data-driven numerical examples
    select-star\       Fabric SELECT-star schema examples
```

The basic verification procedures remain embedded in the root `install.sql`, keeping
one deployment source. Folder names do not change SQL schemas or test selection.
Paths below are relative to the repository root; the PowerShell harnesses also work
from other working directories because they resolve dependencies from their own files.

Install optional packages after `install.sql`, then execute their paired run scripts.
The four optional installers create procedures without executing tests. The framework
installer also adds missing standard global vectors without clearing existing registrations.
None of these packages requires new dimension domains. The main `install.sql`
still installs the framework and runs basic verification.

| Group | Install | Additional tests | Run | Coverage |
|---|---|---:|---|---|
| Regression | [install-framework-coverage-tests.sql](tests/regression/install-framework-coverage-tests.sql) | 16 | [run-framework-coverage-tests.sql](tests/regression/run-framework-coverage-tests.sql) | 49 scenario groups, including 33 basic/positive procedures (41 cases). |
| Sample: catalog | [install-compare-resultset-tests.sql](tests/samples/catalog/install-compare-resultset-tests.sql) | 12 | [run-compare-resultset-tests.sql](tests/samples/catalog/run-compare-resultset-tests.sql) | All installed `sys`-schema tests: 13 shipped comparisons, including basic tables. |
| Sample: STDEV | [install-stdev-tests.sql](tests/samples/stdev/install-stdev-tests.sql) | 27 | [run-stdev-tests.sql](tests/samples/stdev/run-stdev-tests.sql) | All installed `stdev` concept tests: 28 shipped cases, including basic. |
| Sample: SELECT-star | [install-select-star-tests.sql](tests/samples/select-star/install-select-star-tests.sql) | 50 | [run-select-star-tests.sql](tests/samples/select-star/run-select-star-tests.sql) | Explicit-query oracles for SELECT-star projections; no CTAS tests. |

The standalone [vector-tests.sql](tests/regression/vector-tests.sql) and
[dimension-tests.sql](tests/regression/dimension-tests.sql) remain execution suites with
37 and 29 scenarios.
They create and clean disposable fixtures in a clean test database/session.

### Local release check (SQL Server)

Run the complete local test group with one command:

```powershell
.\tests\regression\run-regression-tests.ps1 -Server '.\SQLEXPRESS' -MutationChecks
```

Requires PowerShell, `sqlcmd`, Windows authentication and SQL Server 2022+ permission
to create a database. The harness creates a uniquely named database and drops only that
database in `finally`, including on failure. It never reuses an existing database.
Large dimension-limit cases can take several minutes.

The check includes installation/uninstallation, all SQL regression suites, runner
selection, catalog/STDEV samples and all 72 bundled procedures (80 cases). The
SELECT-star package is installed but its Fabric-only syntax is not executed locally.
Test groups overlap; their counts must not be added into a coverage percentage.

Additional focused checks:

| Harness | Checks |
|---|---|
| [assertion-tests.sql](tests/regression/assertion-tests.sql) | 62 independent cases: result values/counts/order, missing versus NULL properties, long results, query errors, schema signatures/types/lengths/scales, blank arguments and probe cleanup. |
| [logger-tests.ps1](tests/regression/logger-tests.ps1) | 13 exact InfoMessage/PRINT checks: formatting, NULL/empty data, literal `%`, inline boundaries, long chunks, trailing spaces, Unicode and metadata tails. |
| [installation-tests.ps1](tests/regression/installation-tests.ps1) | Rejected install/uninstall calls with XACT_ABORT OFF/ON, with and without outer CATCH; legacy retirement; repeated uninstall preserving user objects and both registry multisets. Run before optional installation. |

`-MutationChecks` also replaces each of `assert_resultset_equals`, `get_query_schema`,
`assert_schema_signature`, `assert_query_schemas_equal` and `log` with a signature-preserving `RETURN`
inside the owned database. Each must be detected by its tests. The original definitions
are restored and rechecked. This is five selected mutation controls, **not** measured
line/branch coverage or a comprehensive mutation score.

### Package selection

The catalog and STDEV installers retain their existing procedure generators. Framework
definitions remain conditionally generated after preflight. Run scripts do not install
persistent procedures or register cases; disposable framework scenario helpers are created
only during execution and then cleaned up.

Run scripts discover their groups rather than repeat every procedure name. Catalog tests
use `test.run @test_schemas = N'tests', @test_object_schemas = N'sys'`. STDEV tests have no
object schema, so their runner selects the `[tests].stdev@%` name pattern.
SELECT-star tests use their own procedure schema and
run with `test.run @test_schemas = N'select_star'`. New tests in these groups are included automatically.
The framework suite deliberately retains a single positive-test list: schema-wide discovery
would include unrelated user tests or deliberately failing runner probes.

`@test_schemas` filters **test-procedure containers**. `@test_object_schemas` filters the parsed
tested-object schema instead. Existing object-filter calls must migrate to the latter.
With no selectors, `EXEC test.run;` still runs only procedures in `tests`.

The basic and three retained optional packages together provide 72 distinct procedures:
17 basic + 16 framework + 12 catalog + 27 STDEV. The independent SELECT-star package
is not included in this count. Reinstallation still runs only the seventeen basic
procedures. `EXEC test.run;` retains its existing meaning: run every
discovered test, including optional and user tests. The basic naming validator
still checks all registered names, even when only basic tests are selected.

### JSON result comparison

`test.is_equal` retains its text/NULL and lossless numeric-string shortcuts. Otherwise,
valid JSON is compared by `test.is_json_equal`: integer row index, property
name, raw value and JSON type. Row order matters; property order does not. Use
matching `ORDER BY` clauses when building the two result sets. JSON numbers such
as `1` and `1.0`, and different date-string formats, are not converted to a common
representation. Values follow SQL comparison rules, including collation/padding.

Scalar numeric-string equality is limited: its `decimal(30,20)` shortcut rejects lossy
fractional conversions instead of rounding different tiny values into equality. Equivalent
spellings beyond that precision may compare unequal. Do not use
`assert_equals` as an arbitrary-precision numeric comparator. For FLOAT inputs use
`assert_float_equals` with an explicit absolute tolerance; for exact decimal values,
compare typed values independently and assert the resulting bit. See the
[numeric comparison contract](docs/api.md#testis_equal).

This is a shallow comparison for result sets with unique column names of at most
128 characters, not recursive JSON equality. The normalizer and experimental
scripts are removed. Reinstallation retires the obsolete framework-owned
normalization tests; unrelated user tests remain. Run
**[install-compare-resultset-tests.sql](tests/samples/catalog/install-compare-resultset-tests.sql)** for
12 additional ordered catalog comparisons, alongside the basic tables comparison.

### Comparing two SELECT statements

`test.assert_resultset_equals` accepts a message and two query strings, adds
`FOR JSON PATH, INCLUDE_NULL_VALUES` to each, and passes the captured results to
`test.assert_equals`. It is a stored procedure: SQL Server functions cannot
execute dynamic SQL.

```sql
EXEC test.assert_resultset_equals
    @message = N'Table names must match',
    @expected_query = N'SELECT name FROM sys.objects WHERE type = N''U''
                        AND is_ms_shipped = 0 ORDER BY name',
    @actual_query = N'SELECT name FROM sys.tables
                      WHERE is_ms_shipped = 0 ORDER BY name';
```

Supply one SELECT statement per string, without an existing `FOR JSON` clause.
An optional final semicolon and surrounding whitespace are accepted. CTEs,
top-level set operators and multiple-statement batches are not supported.
Put UNION/EXCEPT/INTERSECT inside a derived table instead. Use matching `ORDER BY` clauses;
row order matters, but column order does not. NULL properties are retained.
Empty results compare as `[]`, without comparing their column metadata.

**Fabric limitation:** this data helper, the catalog/data samples and some basic tests
capture scalar `FOR JSON` subqueries, which the documented Warehouse surface does not
support. SQL Server success does not validate those paths on Fabric. Schema assertions
avoid that construct; Fabric execution, including extended SELECT-star operators, still
requires a separate endpoint run.

Queries execute sequentially as the caller and must be trusted SQL, not untrusted
user input; this helper does not enforce read-only access. Caller-local variables
are not visible inside the dynamic batches. Use stable data or an appropriate
caller transaction when consistency across both reads matters. Mismatches raise
normal assertion failures; SQL execution errors propagate unchanged.

### Comparing SELECT schemas

Use `test.assert_query_schemas_equal` for two queries, or `test.assert_schema_signature` for a
query and an explicit schema. They compare ordered column names and base SQL
types, including lengths, precision and scale, without reading result rows.
Column names are case-sensitive; nullability and collations are not compared.

```sql
EXEC test.assert_query_schemas_equal N'Projection',
    N'SELECT CAST(1 AS int) AS id, CAST(NULL AS varchar(20)) AS name',
    N'SELECT CAST(99 AS int) AS id, CAST(''alpha'' AS varchar(20)) AS name';

EXEC test.assert_schema_signature N'Expected columns',
    N'[id] int, [name] varchar(20)',
    N'SELECT CAST(1 AS int) AS id, CAST(NULL AS varchar(20)) AS name';
```

Queries must be trusted, single, view-compatible SELECTs with unique named
columns. CTEs are supported; ORDER BY needs TOP or OFFSET. The caller needs
`CREATE VIEW` and permission to alter schema `test`: the shared metadata reader
creates and cleans a uniquely named view without materializing data. This avoids
Fabric's scalar `FOR JSON` restriction. See [API details](docs/api.md#testassert_query_schemas_equal).

The independent [SELECT-star package](tests/samples/select-star/install-select-star-tests.sql) uses these
built-in assertions for 50 query-contract tests over system views, mainly `sys.objects`.
Every test follows AAA: Arrange hardcodes an explicit reference SELECT, Act prepares
the SELECT-star query, and Assert compares ordered names and types with
`test.assert_query_schemas_equal`. Reference columns are never generated from the actual
query or catalog metadata. Basic operators and combinations come first, using direct
`SELECT ... FROM sys.objects` queries that differ only in their SELECT lists. Derived
inputs and `WITH` are reserved for the marked edge cases that specifically test
nested query contexts.

| Area | Contracts |
|---|---|
| Individual operators | LIKE/NOT LIKE percent, underscore, escaped underscore and bracket patterns; EXCLUDE first/last/multiple columns; RENAME aliases and order; REPLACE expressions, date/length/precision changes |
| Combinations | LIKE with EXCLUDE, RENAME or REPLACE; NOT LIKE with RENAME/REPLACE; EXCLUDE/RENAME/REPLACE; RENAME/REPLACE; the full filter/exclude/rename/replace chain |
| Query contexts | Qualified and multiple stars, joins, derived queries, CTE chains, UNION ALL, DISTINCT, TOP/WHERE, empty inputs, correlated expressions, aggregates, PIVOT and UNPIVOT |
| Value checks | Four REPLACE cases also use `test.assert_resultset_equals` on the single `test.run` catalog row, including a same-type replacement that metadata alone cannot detect |

Both query strings are independently written, with the expected aliases, expressions
and column order visible beside the operator being tested. The single-row value checks
avoid row-order ambiguity and concurrent metadata-probe rows. Tests create no input
tables, insert no fixtures and contain no transaction checks; schema assertions still
create and clean metadata views.
The four CTAS tests are removed, including their old procedures during package upgrades.
This package no longer covers table materialization.

Install the updated framework first, then the package; execute
[run-select-star-tests.sql](tests/samples/select-star/run-select-star-tests.sql) to call the standard runner for its
schema; the shipped package contains 50 procedures. Native runner reporting, failure limits,
vectors and dimensions now apply. Nonzero RETURN codes retain the framework's existing
non-error meaning. Individual calls such as
`EXEC select_star.test_like_suffix;` still work. `EXEC test.run;` does not include this
schema unless explicitly selected.

For SQL Server, [installation-tests.ps1](tests/regression/installation-tests.ps1) verifies legacy-sentinel
upgrade cleanup and preservation of caller transactions. It reinstalls the framework;
use an existing dedicated test database.

For SQL Server, [runner-tests.ps1](tests/regression/runner-tests.ps1) verifies standalone script discovery,
isolation, schema/pattern filters, escaped names, registrations and empty selection. It uses
Windows authentication, requires an existing dedicated test database, and removes only its
uniquely named probe objects. It does not verify Fabric's SELECT-star syntax.

```powershell
.\tests\regression\runner-tests.ps1 -Server '.\SQLEXPRESS' -Database 'your_dedicated_test_database'
```

### Explicit message formatting

`test.format_message` and `test.log` no longer automatically format typed dates
or binary values. Existing callers that rely on that behavior must convert them
before passing parameters: use style 126 for ISO dates/timestamps and style 1 for
hex with a `0x` prefix. Text is preserved; numeric substitution, `<null>` and
unassigned-placeholder behavior are unchanged. The existing 4,000-character
per-parameter limit remains.

```sql
DECLARE @utc datetime2(6) = SYSUTCDATETIME();
DECLARE @timestamp nvarchar(33) = CONVERT(nvarchar(33), @utc, 126);
DECLARE @hex nvarchar(4000) = CONVERT(nvarchar(4000), 0x010203, 1);

SELECT test.format_message(N'At %1: %2', @timestamp, @hex, DEFAULT, DEFAULT);
EXEC test.log @message = N'At %1: %2', @p1 = @timestamp, @p2 = @hex;
```

`SYSUTCDATETIME()` supplies UTC in this example. Formatting does not convert time
zones or append `Z`: a `datetime`/`datetime2` value alone does not identify a zone.
Raw dates/binary still fit the `sql_variant` signature but receive only ordinary
text conversion, not the former date/hex formatting.

### Extended Fabric framework tests

After `install.sql`, execute the entire
[install-framework-coverage-tests.sql](tests/regression/install-framework-coverage-tests.sql), including
every `GO` batch. It installs sixteen positive procedures and adds missing standard
global vectors: four POWER and six typed-argument cases. Repeating installation adds
no duplicate standard vectors and preserves the caller's SQL Server scope.

Then execute the entire
**[run-framework-coverage-tests.sql](tests/regression/run-framework-coverage-tests.sql)** in one dedicated
test-Warehouse session, including **every `GO` batch**. It runs these tests with all
seventeen basic procedures and exercises
runner behavior using disposable fixtures. The final two result grids show
`scenario/status/detail` and `coverage_result/failed_groups/known_bug_groups`.

| Area | Scenarios |
|---|---|
| Each assertion and error/fail helper | Success, expected failures, NULL boundaries, error numbers/patterns and no-error markers |
| Equality and JSON comparison | Raw numeric/date spelling, JSON types, ordered rows, property ordering, missing/NULL fields, Unicode, large values |
| Formatting | All parameter positions, explicit ISO/hex text, NULL/default values, Unicode, repeated placeholders and date/hex-like text |
| Logger | SQL smoke checks plus 13 exact output checks in the separate local PowerShell harness |
| Vector scope and arguments | Mutable session/global context, rejected scope values, BIGINT limits, decimal/scientific literals, bit, Unicode/quotes/commas, date/datetime2, binary, NULL and DEFAULT |
| Runner | Discovery, filters, custom/default logger, callbacks, snapshot selection, result classification, rollback, failure limits, RETURN codes, duplicates and reporting errors |

On both engines the positive run reads installed global vectors without registering or
replacing them. SQL Server restores the caller's scope; Fabric skips mutable-session-scope
checks. Pre-existing caller registration tables are rejected without changing their contents.
The runner rejects missing standard vectors and asks for reinstallation. Use a dedicated
test database with only the standard registrations for the selected procedures: extra
vectors or dimension domains change the strict 41-case expectation and fail completeness.
Unrelated registrations are neither selected nor cleared. After explicitly resetting its
vectors, the typed test can also check its default arguments.

There are **49 scenario groups**, not measured 100% line/branch coverage.
The expected result is **`PASSED`, zero failed groups and zero known bugs**; the
`known_bug_groups` column is retained for result-shape compatibility. All thirty-three
positive/bundled procedures (41 cases) must succeed. See [Behavior changes](CHANGES.md)
for the corrections and the ordered/raw JSON comparison contract.

**Expected errors are intentional:** the final duplicate probe emits error 50000
outside `TRY/CATCH` to test continuation. The editor can flag that batch as failed;
continue through the last batch and inspect the final grids. An incomplete suite
cannot report success, and real failed checks raise 51099 after cleanup.

The script rejects colliding fixture/helper names before registration and removes
only procedures created by that run. Rejected runs preserve caller transactions.
Successful runs retain only the positive tests. To rerun one, for example:

```sql
EXEC test.run @test_names = N'[tests].[test.assert_null@fc_null]';
```

Add your own positive procedures alongside the existing ones and append their
full names to `@positive` in the script. Use a dedicated test Warehouse and do not
run concurrent schema changes. Existing user tests are excluded from execution
by the default-discovery probe; pipe-containing procedure names are rejected
because the framework's pipe-delimited exclusion list cannot safely encode them.
The bundled naming-convention check still inspects existing test names. If a run
is cancelled, execute the procedure-cleanup portion of the final batch before using
unfiltered `test.run`.

### 2. Write a test

Create a stored procedure inside `tests`. The procedure name encodes the object you test:

```
[tests].[<schema>.<object>][@<action>]
```

* `<schema>` – schema of the object under test (e.g. `sales`)
* `<object>` – object name (`usp_create_order`)
* `@<action>` – *optional* scenario / edge‑case tag

For a concept rather than a physical database object, use `[tests].[<object>@<action>]`,
for example `[tests].[stdev@sin_1000]`. Both parts are required. The naming validator
skips object-existence checks for this form; schema-qualified names retain their
existing checks. No default target schema is assigned, and dots after `@` belong to
the action. Conceptual tests run normally under container `@test_schemas` filters; they have
no object schema to match `@test_object_schemas`.

[install-stdev-tests.sql](tests/samples/stdev/install-stdev-tests.sql) registers 27
additional such tests. Rerunning it replaces its legacy
`math.stdev@...` procedures with `stdev@...` names, without removing unrelated tests.
On an existing installation with the legacy names, rerun that file before reinstalling
the framework because the basic naming validator still inspects those old targets.

#### Use AAA and choose cleanup explicitly

Keep declarations and boilerplate before `-- Arrange`, prepare inputs and independent
expectations in Arrange, execute the behavior in Act, and verify it in Assert.
The [three recipe pages](docs/static-test-recipes.md) use built-in functions and do not
modify application data.

For tests that write transactional data, use explicit rollback on success and failure.
The following application-specific example requires `sales.usp_create_order` and its
test fixtures to exist; it is not a standalone built-in recipe:

```sql
CREATE OR ALTER PROCEDURE [tests].[sales.usp_create_order@happy_path]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @customer_id int, @order_id int, @order_bytes varbinary(max);

    -- Arrange
    SET @customer_id = 1;
    BEGIN TRAN;
    BEGIN TRY
        -- Act
        EXEC @order_id = sales.usp_create_order @customer_id;
        SET @order_bytes = CONVERT(varbinary(max), @order_id);

        -- Assert
        EXEC test.assert_not_null N'Order id must be generated', @order_bytes;
        ROLLBACK;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
```

Any uncaught exception fails the test automatically.

### Run tests

T‑TEST provides two convenient ways to execute your tests:

1. Via the runner **\[test].\[run]**
2. **By calling the test procedure directly**

#### 1. Using `test.run`

```sql
-- run all tests in the default tests container
EXEC test.run;

-- run all test procedures contained in the sales schema
EXEC test.run @test_schemas = N'sales';

-- run tests of objects in sales, stored in the tests container
EXEC test.run @test_object_schemas = N'sales';

-- run all procedures in a quoted schema through a LIKE pattern
EXEC test.run @test_names = N'[select_star].%';

-- run a specific test and stop on first failure
EXEC test.run
      @test_names        = N'[tests].[sales.usp_create_order@happy_path]|[tests].[inventory.adjust_stock@edge_case]',
      @exclude_test_names = N'[tests].[obsolete.some_legacy_test]',
      @test_schemas       = N'tests',
      @test_object_schemas = N'sales,inventory',
      @exclude_test_object_schemas = N'legacy',
      @max_failures       = 5,              -- stop after 5 failures
      @before_each_sql    = N'SET NOCOUNT ON',
      @log_proc_name      = N'test.log';

```

`test.run` prints a concise summary and **throws** if any test fails, giving `sqlcmd` or your CI pipeline a non‑zero exit code:

```
################################################################################################
Running [tests].[sales.usp_create_order@happy_path]
INFO: 5 tests executed. Succeeded: 5, failed: 0, errors: 0
```

The first result table has four columns:

| Column | Meaning |
|---|---|
| `test` | Test procedure name. |
| `duration, s` | Execution time in seconds, with one decimal place. |
| `status` | `PASS` or `FAIL`; both assertion failures and unexpected exceptions are `FAIL`. |
| `failure_reason` | `NULL` for `PASS`; otherwise `Assertion failed: ...` or `Unexpected exception: ...`. |

Expected exceptions that are caught and verified inside a test still produce `PASS`.
The former `is_success`, `is_failed` and `is_error` output columns are removed;
update consumers that depend on those columns. Internal classification, summary
counts, failure limits and the second result table (duration by schema) are unchanged.

#### 2. Executing a test procedure directly

You can execute a single static test directly. Cleanup is the test's responsibility;
direct execution does not add a transaction or invoke runner callbacks:

```sql
EXEC [tests].[sales.usp_create_order@happy_path];
```

Parameterized tests need arguments when executed directly; use the runner to replay
their saved vectors or dimensions.

---

### Vector parameters

**Global storage is the default.** Installation provisions the table; register trusted
SQL argument lists and keep using the existing `test.run` interface.

```sql
CREATE OR ALTER PROC [tests].[test.assert_equals@vector_example]
    @expected nvarchar(max), @actual nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @equal bit;

    -- Arrange
    --N/A

    -- Act
    SET @equal = test.is_equal(@expected, @actual);

    -- Assert
    EXEC test.assert_equals N'Vector predicate must report equality', 1, @equal;
END;
GO

EXEC test.vector N'[tests].[test.assert_equals@vector_example]', N'1, 1';
EXEC test.vector N'[tests].[test.assert_equals@vector_example]', N'NULL, NULL';
EXEC test.run @test_names = N'[tests].[test.assert_equals@vector_example]';
```

Every stored row executes, including duplicates. Procedures without registrations retain
their single static call. Saved global cases can be run from later connections.
On SQL Server, for ad hoc cases, create `#test_vectors` with the columns documented in the API.
Create it in the calling batch and call `EXEC test.set_registration_scope N'session';` once on that connection.
No scope parameter is added to registration, reset or run.
Fabric Warehouse supports global scope only; `test.set_registration_scope N'session'` raises an error.

`EXEC test.clear_registrations;` clears vectors and dimensions only in the chosen store, without dropping tables or changing
scope. Global reset affects every user sharing those definitions. Missing tables warn
and skip registration; the runner/reset silently continue without that source.
Reset also removes the shipped POWER vectors; rerun `install.sql` to restore them.
Use `EXEC test.clear_registrations @test_name = N'[tests].[WELCH_TEST@generate_series]';`
to clear only one procedure's vectors and dimensions in that store.
See [vector APIs](docs/api.md#testvector) for storage, logging and trust-boundary details.

### Dimension parameters

Use `test.dimension` for independent parameter domains. Two values for `@number`
and three for `@text` produce six named-argument calls to `replicate@dimensions`.
Explicit vectors run first and are added to, not multiplied by, that product.
Duplicate values remain separate cases.

Create `[test].[test_dimension_values]` yourself for global storage, or
`#test_dimension_values` in the calling batch for session storage on SQL Server. See the
[dimension API example](docs/api.md#testdimension) for the table definition and registration.
The installer checks the built-in REPLICATE example using temporary global domains,
restores saved domains, and removes dimension storage only if it created it.
The mixed session/global vector and dimension diagnostic suites skip on Fabric Warehouse;
the installer's global examples still run.

## 📦 Example project

A full working demo that uses T‑TEST for its database layer lives here:

[t‑chess ▶ ](https://github.com/uratol/t-chess)

Explore the `tests` folder to see real‑world tests written with the patterns shown above.

---

## 🔒 Transactions: when to wrap and when to skip

### Why wrap in `BEGIN TRAN … ROLLBACK`

1. **Transactional cleanup** - rollback can undo participating inserts, updates and
   transactional DDL; handle both success and failure explicitly.
2. **Known exceptions** - identity/sequence values consumed during a test are not
   restored by rollback. External effects and other sessions are not rolled back.
3. **Repeatability** - use controlled fixtures; a transaction alone does not guarantee
   an identical starting state or prevent blocking and interference.
4. **Shared databases** - coordinate global registrations and schema changes.
   Prefer dedicated disposable test databases over production or shared mutable data.

### When *not* to wrap

Some behaviours rely on a *real commit* and therefore **must run outside a manual transaction**:

* **Service Broker** – message delivery, queue activation, and conversation state changes happen only after the outer transaction commits.
* **SQL Agent jobs / sp\_start\_job** – the job fires in another session; holding a transaction open can delay or block its execution.
* **Commit‑driven features** – triggers that enqueue work to other systems, Change Data Capture, replication, Query Notifications.
* **Cross‑session concurrency tests** – scenarios where one connection must commit so another can observe locks or row versions.

In those cases, omit `BEGIN TRAN / ROLLBACK` and either:

* Run against disposable test data, or
* Add explicit cleanup at the end of the test.

Neither approach automatically undoes external effects. The runner rejects an existing
caller transaction and, on SQL Server, implicit transactions; tests manage their own
transactions. Fabric Warehouse supports global registration scope only.

---

## 📚 Test examples

### 1. Basic equality assertion

```sql
CREATE OR ALTER PROCEDURE [tests].[math.add@positive]
AS
BEGIN TRAN
    DECLARE @result int;

    EXEC @result = math.add @a = 20, @b = 22;

    -- Should return 42
    EXEC test.assert_equals N'20 + 22 must be 42', 42, @result;
ROLLBACK;
```

### 2. Recordset comparison (no temp tables needed)

```sql
CREATE OR ALTER PROCEDURE [tests].[api.get_users@ordering]
AS
BEGIN TRAN
    EXEC test.assert_resultset_equals
        N'Users must match',
        N'SELECT * FROM (VALUES (1, N''Ann''), (2, N''Bob'')) v(id, name) ORDER BY id',
        N'SELECT * FROM dbo.get_users() ORDER BY id';
ROLLBACK;
```

### 3. Exception testing

```sql
CREATE OR ALTER PROCEDURE [tests].[sales.usp_create_order@invalid_customer]
AS
BEGIN TRAN
    BEGIN TRY
        -- Call the object under test which is *expected* to raise
        EXEC sales.usp_create_order @customer_id = -1;  -- invalid id triggers validation error
        -- Sentinel helper – forces failure if exception was **not** thrown
        EXEC test.fail_no_error;
    END TRY
    BEGIN CATCH
        EXEC test.assert_error N'Invalid customer validation',
            50001, N'%invalid customer%', DEFAULT;
    END CATCH;
ROLLBACK;
```

### 4. Inline `test.fail` inside a `WHERE` clause

```sql
CREATE OR ALTER PROCEDURE [tests].[security.is_admin@assert_role]
AS
BEGIN TRAN
    /*
       Fail the test *only* when the condition is true.
       Here we assert that the current login must belong to the db_owner role.
    */
    SELECT test.fail('Current login must be a member of db_owner')
    WHERE IS_MEMBER('db_owner') = 0;
ROLLBACK;
```

---

## 🧪 Implementation tricks

### 1. **Assertion procedures reuse predicates**

Every `assert_*` helper is a stored procedure. Value assertions call the corresponding
`is_*` bit predicate and fail only when it returns 0. `assert_equals` uses the canonical
`is_equal`; `is_equals` remains a compatibility alias. `assert_error` directly
checks the current CATCH context; it has no `is_error` counterpart.

```sql
SELECT test.is_equal(N'001.50', N'1.5'); -- 1, no assertion
EXEC test.assert_equals N'Values must match', N'001.50', N'1.5';
```

Assertions raise native error 70001 with the `Unit-test fail:` marker through
`test.throw`; the runner distinguishes this from unexpected errors. Compute expression
arguments into local variables before `EXEC`, or use `assert_resultset_equals` for queries.
This replaces the scalar assertion API: custom `SET @r = test.assert_*(...)` and
`SELECT test.assert_*(...)` callers must migrate to `EXEC`. The installer refreshes
shipped callers, but does not rewrite user tests.
Likewise, replace `SET @r = test.fail_no_error()` with `EXEC test.fail_no_error;`.

### 2. **Legacy failures from a function**

The retained `fail` and `throw_error` functions still use a type-mismatch
trick because SQL Server forbids `THROW` inside scalar UDFs. Assertions no longer need it:

```sql
IF TRY_CAST(LEFT(@error_message, 4000) AS int) IS NOT NULL
    SET @error_message = N'Error: ' + @error_message;
RETURN CAST(LEFT(@error_message, 4000) AS int);  -- inside test.throw_error()
```

* The function returns **nvarchar(max)**, but forces an integer conversion before returning.
* Numeric and empty/whitespace messages receive a non-numeric prefix so they cannot silently succeed. NULL still returns NULL.
* The forced `CAST` raises conversion error **245** (`Conversion failed when converting the nvarchar value '<our_error_message>' to data type int`).
* That error propagates just like a normal `THROW`, so the outer `TRY…CATCH` (or the framework runner) can handle it.

No special flags or return‑value checks—SQL Server itself turns the failed cast into a real exception.

### 3. Ordered JSON result comparison

After text/NULL and scalar numeric shortcuts, `test.is_equal` delegates to
`test.is_json_equal`. The helper compares row indexes, property names, values
and JSON types using `OPENJSON`, `OUTER APPLY` and a `FULL OUTER JOIN`.

Property order is ignored, but row order and multiplicity matter. For example,
`{"a":1,"b":2}` equals `{"b":2,"a":1}`, whereas `[1,2]` differs from `[2,1]`.
JSON numeric spellings such as `[1]` and `[1.0]` also differ. Use matching
`ORDER BY` clauses when capturing queries with `FOR JSON PATH`.

Inputs are `nvarchar(max)` and the result is a bit. Unicode does not require a
UTF-8 database collation. SQL collation and padding rules still apply to values.
The intended inputs are shallow result sets with unique column names of at most
128 characters; nested values are compared as raw JSON text, not recursively.
There is no normalizer or backup-based restoration step.

### 4. **Auto‑discovering tests via a view**

The view `[test].[test]` parses procedure names in the `tests` schema to locate:

* The **tested object** (`schema.object`).
* An optional **action tag** after `@`.

No extra metadata tables are needed; naming convention = registration.
The neutral `[test].[test_procedures]` view exposes the same parsed metadata plus procedure
schema and ID across all containers; `test.run` uses it for explicit schema/name selection.
Explicit selectors treat every matching stored procedure as a test. Use dedicated test
schemas: an unrestricted `%` pattern can also select application or framework procedures.

```sql
-- list all registered tests with their target objects and parsed metadata
SELECT *
FROM   test.test;
```

### 5. **Sentinel‑style exception testing**

A concise pattern for verifying that a call *does* raise the expected error and that the error’s properties are correct.

1. **Act** – run the statement expected to fail.
2. **Sentinel** - execute `test.fail_no_error` immediately after; missing errors fail the test.
3. **Assert** - inside `CATCH` use `test.assert_error` with the required filters.

```sql
BEGIN TRY
    EXEC sales.usp_create_order @customer_id = -1;  -- (1) act
    EXEC test.fail_no_error; -- (2) sentinel
END TRY
BEGIN CATCH                                         -- (3) assert
    EXEC test.assert_error
        N'Invalid customer validation', 50001, N'%invalid customer%', DEFAULT;
END CATCH;
```

`EXEC test.fail_no_error` raises native assertion error 70001 with the missing-error
sentinel; place it directly
after the call expected to fail. It replaces the former `test.error()` name.
Rerunning `install.sql` updates bundled tests and retires the legacy function and
coverage-test name. Update calls and helper-target procedure names in your own
tests; no compatibility alias remains.

**Why it’s neat**

* **Pure T‑SQL**—no CLR interception or internal flags.
* **Granular**—assert any part of the error record, even run extra queries in the `CATCH`.
* **Transparent**—you control the flow; unlike `tSQLt.ExpectException`, the logic is visible and customisable.

*Quick comparison to tSQLt*: with `tSQLt.ExpectException` you declare expectations **before** the call and rely on the framework’s hidden interception. T‑TEST’s sentinel style is a few lines longer but offers richer assertions and works on servers where CLR is disabled.

---

## 🛠 Assertion toolbox

| Helper                                           | Purpose                                                        | Example                                                               |
| ------------------------------------------------ | -------------------------------------------------------------- | --------------------------------------------------------------------- |
| `test.assert_equals @message, @expected, @actual` | smart equality through is_equal | `EXEC test.assert_equals N'Should be 42', N'42', @val;` |
| `test.assert_float_equals @message, @expected, @actual, @tolerance` | FLOAT equality through is_float_equal | `EXEC test.assert_float_equals N'Deviation', @expected, @actual, 1E-12;` |
| `test.assert_resultset_equals @message, @expected_query, @actual_query` | Compare two SELECT results; stored procedure | `EXEC test.assert_resultset_equals N'Rows', N'SELECT 1 AS id', N'SELECT 1 AS id';` |
| `test.assert_query_schemas_equal @message, @expected_query, @actual_query` | Compare ordered output column names and types | `EXEC test.assert_query_schemas_equal N'Schema', N'SELECT 1 AS id', N'SELECT 99 AS id';` |
| `test.assert_schema_signature @message, @expected_schema_signature, @actual_query` | Compare query schema with a canonical signature | `EXEC test.assert_schema_signature N'Schema', N'[id] int', N'SELECT 1 AS id';` |
| `test.assert_error @message, @expected_number, @expected_message_pattern, @expected_state` | Match a caught error; omitted/NULL filters are skipped | `EXEC test.assert_error N'Expected message', @expected_message_pattern = N'%Invalid customer%';` |
| `test.assert_not_null @message, @value` | Require is_not_null = 1 | `EXEC test.assert_not_null N'Required', @value;` |
| `test.assert_null @message, @value` | Require is_null = 1 | `EXEC test.assert_null N'Expected NULL', @value;` |
| `test.fail(msg)`                                 | fail immediately, you can add your conditions in WHERE section | SELECT `test.fail('Not implemented')` WHERE IsAdmin(@my\_profile) = 0 |
| `test.fail_no_error` | Fail when an expected exception did not occur; place after the tested call | `EXEC test.fail_no_error;` |
|                                                  |                                                                |                                                                       |

`assert_float_equals` returns normally on success and raises an assertion failure on
mismatch. `@tolerance` is the maximum absolute difference, not a decimal
digit count or relative percentage; it must be non-NULL and non-negative. Zero
requires exact equality. Two NULL values match; one NULL fails. STDEV tests pass
their reference, measured result and tolerance directly, without manual difference
checks. The extended STDEV suite derives its absolute tolerance from an absolute
floor plus a relative allowance.

`assert_error` must be called inside `CATCH`. It reads `ERROR_NUMBER()`,
`ERROR_MESSAGE()` and `ERROR_STATE()`, not the statement-local `@@ERROR`.
Each optional filter defaults to NULL: only supplied values are checked. Message
matching uses SQL `LIKE` through `@expected_message_pattern`; pass `N'%fragment%'`
to find text within the message.
Use `[%]`, `[_]` and `[[]` to match literal wildcard characters.
All-NULL filters still require a genuine caught error. Outside CATCH and for the
`test.fail_no_error` no-error sentinel, the assertion fails. Optional filters can
be omitted or supplied by name.

```sql
BEGIN TRY
    EXEC test.assert_float_equals N'Different values', 1, 2, 1E-12;
    EXEC test.fail_no_error;
END TRY
BEGIN CATCH
    EXEC test.assert_error N'Different floats must fail', 70001;
END CATCH;
```

---

## ⚙️ Runner options

```sql
EXEC test.run
      @test_names        = N'[tests].[sales.usp_create_order@happy_path]|[tests].[inventory.adjust_stock@edge_case]',
      @exclude_test_names = N'[tests].[sales.usp_create_order@obsolete]',
      @test_schemas       = N'tests',
      @test_object_schemas = N'sales,inventory',
      @exclude_test_object_schemas = N'legacy',
      @max_failures       = 5,              -- stop after 5 failures
      @before_each_sql    = N'SET NOCOUNT ON',
      @log_proc_name      = N'test.log';
```

| Parameter                       | Default      | Description                                                         |
| ------------------------------- | ------------ | ------------------------------------------------------------------- |
| `@test_names`                   | `NULL`       | Pipe-separated exact names or SQL LIKE patterns to include |
| `@exclude_test_names`           | `NULL`       | Pipe-separated exact names or SQL LIKE patterns to exclude |
| `@test_schemas` / `@exclude_test_schemas` | `NULL`       | Filter by test-procedure container schema |
| `@test_object_schemas` / `@exclude_test_object_schemas` | `NULL` | Filter by parsed tested-object schema |
| `@max_failures`                 | `1 000 000`  | Fail‑fast after N failures                                          |
| `@before_each_sql`              | `NULL`       | T‑SQL executed before each test (e.g. `DBCC DROPCLEANBUFFERS`)      |
| `@log_proc_name`                | `'test.log'` | Plug‑in alternative logger                                          |

Exact names take precedence; otherwise names support SQL LIKE `%`, `_` and bracket
character classes, not `*`. `[select_star].%` treats the quoted schema literally.
Schema and name filters intersect. An unmatched included name/pattern or empty explicit
schema fails instead of producing a false-green run. Exclusions matching nothing are ignored.

---

## 📝 Logging

`test.log` standardises messages (`DEBUG`, `INFO`, `WARNING`, `ERROR`). Pass contextual data via `%1..%4` placeholders:

```sql
EXEC test.log @message = 'Imported %1 rows', @p1 = @@ROWCOUNT, @severity = 'info';
```

Feel free to swap it with your own implementation and point `test.run` to it.

---

## 🤖 CI integration

Add a job after your migration step. This is a pipeline example, not an included
workflow; configure connection/authentication for your test database:

```yaml
- task: SqlAzureDacpacDeployment@1
  inputs:
    sqlFile: migrations.sql
    # …
- script: sqlcmd -b -S $(DbServer) -d $(Db) -Q "EXEC test.run;"
  displayName: "Run T‑SQL unit tests"
```

* `-b` makes `sqlcmd` exit with non‑zero code on `THROW`, so the pipeline fails if tests fail.

---

## 🔄 T-TEST vs. tSQLt

| Area                                       | T-TEST                                                                                                                                                                                                                             | tSQLt                                                                                                                                                               | Take‑away                                                                                     |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| **Deployment** | One authoritative SQL installer; optional test packages are separate. No database-project build or DACPAC deployment. | A separate framework installation with additional testing helpers. | Compare the actual deployed versions; no fixed size claim is made. |
| **How recordsets are compared** | `assert_resultset_equals` compares ordered SELECT data through shallow JSON; schema assertions check column contracts separately. | `tSQLt.AssertEqualsTable` compares named expected and actual tables. | Choose result-data and schema checks according to the contract being tested. |
| **Service Broker & SQL Agent** | Tests can manage their own commit boundaries and cleanup; jobs run in another session and message delivery/activation can require commit. | Transaction-oriented tests also need special handling for asynchronous or commit-driven behavior. | Neither framework automatically rolls back cross-session or external effects. |
| **Test classification**                    | Test procedure name encodes target: `[tests].[schema.object@scenario]` ⇒ quick filtering by schema/object                                                                                                                          | Uses *test classes* (schemas) + procedure name – extra level, but cleaner separation                                                                                | Depends on taste; tSQLt needs no helper commands to create classes                            |
| **Execution flexibility**                  | `test.run` accepts *include / exclude* lists, schema filters, fail‑fast limit, callback hook                                                                                                                                       | `EXEC tSQLt.Run` runs all or a single class; finer filtering requires PowerShell or wrapper scripts                                                                 | T-TEST offers more granular selection out‑of‑the‑box                                          |
| **Helpers & exception handling** | Assertions are **procedures** backed by reusable bit predicates. `assert_error` checks number, LIKE message and state inside CATCH. | Helpers are *procedures*; exception tests use `tSQLt.ExpectException`. | T-TEST keeps comparisons reusable without assertions and error checks explicit. |
| **Mocking / Isolation**                    | Uses your own `BEGIN TRAN / ROLLBACK`; no automatic fake tables                                                                                                                                                                    | Rich mocking: fake tables, spy procedures, `tSQLt.FakeTable`, `tSQLt.SpyProcedure`                                                                                  | tSQLt wins for complex mocks                                                                  |
| **Dependencies**                           | None (pure T‑SQL)                                                                                                                                                                                                                  | CLR enabled (for NUnit‑style output) on older versions, external installer                                                                                          | T-TEST easier on locked‑down servers                                                          |

**When to prefer T-TEST**

* You want a *minimal* framework that piggybacks on plain T‑SQL and works in any environment (Azure SQL DB, managed instances, on‑prem).
* Your primary pain‑point is **assertion verbosity** rather than advanced mocking.
* You need explicit control over transaction boundaries for **Service Broker or SQL
  Agent tests**, with disposable fixtures and separate cleanup for external effects.

**When to stick to tSQLt**

* You rely on its **fake tables / spy procedures** for heavy isolation or mocking.
* You need its **code‑coverage hooks** or integration with existing tSQLt‑based test suites.

---

## 📄 License

[MIT](LICENSE.txt)

---

## 🤝 Contributing

1. Fork / create a feature branch.
2. Add or update objects in `test` schema, add tests inside `tests` schema.
3. Ensure `EXEC test.run` passes.
4. Submit a PR.

Feel free to open issues for bugs or feature requests.

---
