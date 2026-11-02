# T-TEST

A **lightweight, pure‑T‑SQL unit‑testing framework** for SQL Server. Drop‑in installation, zero external dependencies, CI‑friendly output.

For signatures and examples, see the [API reference](api.md).

For the Fabric-oriented refactoring, see [Behavior changes](CHANGES.md), including
intentional compatibility changes, bug fixes and verification limits.

---

## ✨ Features

* **100 % T‑SQL** – no CLR, PowerShell or external test runner required.
* **Self‑discovering tests**: every procedure in the `tests` schema is a test.
* **Rich assertions**:

  * smart equality (ordered recordsets, `NULL`, numbers, JSON)
  * exception pattern matching
  * null / not‑null shortcuts
* **Transactional isolation** – write tests as `BEGIN TRAN / ROLLBACK` so production data is never touched.
* **Minimal footprint** – just helper functions in `test` schema and a view + runner.
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
2. Register and run the **14 basic self-tests** at the end. On a fresh database,
   the summary reports `14 tests of 14 executed. Succeded: 14, failed: 0, errors: 0`.
   Existing additional and user tests are retained, but are not executed by installation.

| Schema  | Purpose                                                |
| ------- | ------------------------------------------------------ |
| `test`  | framework internal objects: runner, assertions, logger |
| `tests` | **your** test procedures live here                     |

### Fabric Warehouse installation

Use **[install.sql](install.sql)** for both SQL Server 2022+ and Fabric Warehouse.
In the Fabric SQL query editor, paste the entire script and run it,
including the `GO` batch separators. Use an account with permission to create
schemas, views, functions and procedures.

The shared installer creates missing schemas and uses `CREATE OR ALTER` for
framework objects and bundled tests. It can repair a partial installation without
deleting existing user tests. It runs only the fourteen basic tests at the end,
and prints completion only after the required objects exist and the
test run returns successfully. Inspect all errors in Messages; installation is
not atomic, and a later batch can run after an earlier batch fails.

The installer runs `test.log` as the caller, without `dbo` impersonation.
Procedure names in logs depend on the caller's metadata visibility.
The deployed runner and SSDT source omit `SET XACT_ABORT`. The installer footer
calls the runner directly on Fabric (EngineEdition 11); elsewhere it executes `SET XACT_ABORT OFF`
and `EXEC test.run` together inside one dynamic batch. Tests and their child
procedures inherit that setting, and the caller's setting is restored afterward.
A direct `EXEC test.run` outside this wrapper inherits the caller's setting instead.
The installer and SSDT sources replace `@@PROCID`
with explicit object-name lookups and avoid nested `FOR JSON` in discovery tests.
There is one installer, without `WITH INLINE = AUTO`.
JSON equality uses `OPENJSON` and a join, not normalization.
Use standalone assertions, such as `SELECT test.assert_equals(...);`, with
precomputed scalar inputs.

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

### Basic verification and additional packages

The basic procedures live in `Source (SSDT project)\tests\Stored Procedures` and
are included in `install.sql`. They use small, static cases:

| Basic test | Checks |
|---|---|
| `test.test` | Discovery and metadata for temporary test procedures. |
| `test.test@name_convention` | Naming and referenced-object validation. |
| `test.format_message` | Substitutions, explicit formatting and a logger smoke check. |
| `test.throw` | THROW, raw errors, fail/no-error helpers and error-number/pattern assertions. |
| `test.assert_equals` | Equal values/NULLs and a caught mismatch. |
| `test.assert_float_equals` | Inclusive absolute tolerance, NULLs, invalid tolerance and extreme FLOATs. |
| `test.assert_resultset_equals` | Compare ordered sys.objects/sys.tables results, including NULLs and typed columns. |
| `test.assert_error` | Optional error number, LIKE message pattern and state; absent/sentinel errors are rejected. |
| `test.assert_not_null` | Ordinary/empty bytes and a caught NULL rejection. |
| `test.assert_null` | NULL and a caught non-NULL rejection. |
| `test.is_equal` | Scalar shortcuts and direct ordered/raw OPENJSON comparisons. |
| `sys.objects@tables` | All 12 shared catalog columns plus schema name, including NULLs. |
| `stdev@basic` | Known sample deviation and one/zero-value NULL boundaries. |
| `data_types@basic` | Independently defined rows of numeric, temporal, text, binary, GUID, NULL and spatial values. |

These are functional self-tests, not exclusively integration tests. They exercise
all eleven scalar functions, the logger/throw helpers, discovery and the runner;
this is not measured line/branch coverage. Expected scalar-UDF failures run outside
explicit transactions. Each test prints two description lines of at most 60 characters.

Basic tests use inline values and separate Arrange, Act and Assert where useful.
Assertion-only examples omit unnecessary setup, JSON case matrices and loops.
Scenario tests use framework assertions: catalog queries capture ordered results
with `SET @json = (SELECT ... FOR JSON PATH)`, and STDEV tests use `assert_null`
or `assert_float_equals` with an absolute tolerance. Framework self-tests use independent comparisons
and `THROW` so a broken assertion cannot validate itself. Value/float assertions
return `N''` on success; error assertions return NULL. Assigning results avoids empty grids.
The query-comparison procedure returns no result grid and is called with `EXEC`.

SYS catalog pairs compare every shared column, including integer IDs, datetime
timestamps and bit flags; none has a shared FLOAT column. INFORMATION_SCHEMA pairs
also compare equivalent catalog, kind, parent and date fields where available.
The inline-row test supplies FLOAT/REAL coverage alongside other scalar types,
Unicode and long strings. Its geometry/geography variables are compared through
`STAsText()` and SRID because `FOR JSON` cannot serialize spatial types directly.
JSON/XML values are excluded; JSON is only the comparison transport.

Install optional packages after `install.sql`. Each script registers and
runs its own package; the framework package also runs the fourteen basic tests.

| Script | Additional tests | Execution |
|---|---:|---|
| [install-framework-coverage-tests.sql](install-framework-coverage-tests.sql) | 14 | 28 basic/positive tests plus 49 runner/framework scenario groups. |
| [install-compare-resultset-tests.sql](install-compare-resultset-tests.sql) | 12 | Additional catalog comparisons; the tables comparison is already basic. |
| [install-stdev-tests.sql](install-stdev-tests.sql) | 27 | LOG/SIN/value series at sizes 0 through 100,000. |

All packages together provide 67 distinct procedures. Reinstallation still runs
only the fourteen basic tests. `EXEC test.run;` retains its existing meaning: run every
discovered test, including optional and user tests. The basic naming validator
still checks all registered names, even when only basic tests are selected.

### JSON result comparison

`test.is_equal` retains its text/NULL and numeric-string shortcuts. Otherwise,
valid JSON is compared by `test.is_json_equal`: integer row index, property
name, raw value and JSON type. Row order matters; property order does not. Use
matching `ORDER BY` clauses when building the two result sets. JSON numbers such
as `1` and `1.0`, and different date-string formats, are not converted to a common
representation. Values follow SQL comparison rules, including collation/padding.

This is a shallow comparison for result sets with unique column names of at most
128 characters, not recursive JSON equality. The normalizer and experimental
scripts are removed. Reinstallation retires the obsolete framework-owned
normalization tests; unrelated user tests remain. Run
**[install-compare-resultset-tests.sql](install-compare-resultset-tests.sql)** for
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
An optional final semicolon and surrounding whitespace are accepted. CTEs and
multiple-statement batches are not supported. Use matching `ORDER BY` clauses;
row order matters, but column order does not. NULL properties are retained.
Empty results compare as `[]`, without comparing their column metadata.

Queries execute sequentially as the caller and must be trusted SQL, not untrusted
user input; this helper does not enforce read-only access. Caller-local variables
are not visible inside the dynamic batches. Use stable data or an appropriate
caller transaction when consistency across both reads matters. Mismatches raise
normal assertion failures; SQL execution errors propagate unchanged.

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

After installation, execute the entire
**[install-framework-coverage-tests.sql](install-framework-coverage-tests.sql)**
in one test-Warehouse session, including **every `GO` batch**. It creates fourteen
positive test procedures, runs them with the fourteen basic tests, and exercises
runner behavior using temporary fixtures. The final two result grids show
`scenario/status/detail` and `coverage_result/failed_groups/known_bug_groups`.

| Area | Scenarios |
|---|---|
| Each assertion and error/fail helper | Success, expected failures, NULL boundaries, error numbers/patterns and no-error markers |
| Equality and JSON comparison | Raw numeric/date spelling, JSON types, ordered rows, property ordering, missing/NULL fields, Unicode, large values |
| Formatting | All parameter positions, explicit ISO/hex text, NULL/default values, Unicode, repeated placeholders and date/hex-like text |
| Logger | NULL, formatted parameters, inline/multiline/chunked output; PRINT text is a smoke check, not automatically captured |
| Runner | Discovery, filters, custom/default logger, callbacks, snapshot selection, result classification, rollback, failure limits, RETURN codes, duplicates and reporting errors |

There are **49 scenario groups**, not measured 100% line/branch coverage.
The expected result is **`PASSED`, zero failed groups and zero known bugs**; the
`known_bug_groups` column is retained for result-shape compatibility. All twenty-eight
positive/bundled test procedures must succeed. See [Behavior changes](CHANGES.md)
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
the action. Conceptual tests run normally but are not selected by `@schemas` filters.

`install-stdev-tests.sql` registers 27 additional such tests. Rerunning it replaces its legacy
`math.stdev@...` procedures with `stdev@...` names, without removing unrelated tests.
On an existing installation with the legacy names, rerun that file before reinstalling
the framework because the basic naming validator still inspects those old targets.

#### Why wrap tests in a `BEGIN TRAN / ROLLBACK`

> **Most T‑TEST samples open a transaction at the very top and roll it back at the end.**
>
> • **Self‑contained execution** – you (or CI) can simply `EXEC [tests].[…]` and the procedure cleans up after itself, leaving no side‑effects.
>
> • **Transaction‑aware flows** – Service Broker dialogs, SQL Agent jobs started with `sp_start_job`, and any trigger‑spawned work all participate in the same transaction, so you can assert on their behaviour *before* the rollback.
>
> • **Zero data pollution** – production tables remain untouched even if the test inserts millions of rows.

Example:

```sql
CREATE OR ALTER PROCEDURE [tests].[sales.usp_create_order@happy_path]
AS
BEGIN TRAN
    ------------------------------------------------------------------
    -- arrange
    DECLARE @customer_id int = 1;
    DECLARE @order_id   int;

    -- act
    EXEC @order_id = sales.usp_create_order @customer_id;

    -- assert
    SELECT test.assert_not_null('Order id must be generated',
                                @order_id);
ROLLBACK;
```

Any uncaught exception fails the test automatically.

### Run tests

T‑TEST provides two convenient ways to execute your tests:

1. Via the runner **\[test].\[run]**
2. **By calling the test procedure directly**

#### 1. Using `test.run`

```sql
-- run absolutely everything
EXEC test.run;

-- run only tests that target objects in the sales schema
EXEC test.run @schemas = N'sales';

-- run a specific test and stop on first failure
EXEC test.run
      @test_names        = N'[tests].[sales.usp_create_order@happy_path]|[tests].[inventory.adjust_stock@edge_case]',
      @exclude_test_names = N'[tests].[obsolete.some_legacy_test]',
      @schemas            = N'sales,inventory',
      @exclude_schemas    = N'legacy',
      @limit_failed       = 5,              -- stop after 5 failures
      @before_callback    = N'SET NOCOUNT ON',
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

Because most tests are wrapped in `BEGIN TRAN / ROLLBACK`, you can execute a single test in SSMS without leaving data behind:

```sql
EXEC [tests].[sales.usp_create_order@happy_path];
```

Perfect for quick debugging and exploratory runs.

---

## 📦 Example project

A full working demo that uses T‑TEST for its database layer lives here:

[t‑chess ▶ ](https://github.com/uratol/t-chess)

Explore the `tests` folder to see real‑world tests written with the patterns shown above.

---

## 🔒 Transactions: when to wrap and when to skip

### Why wrap in `BEGIN TRAN … ROLLBACK`

1. **Run the test ad‑hoc** – simply `EXEC [tests].[…]` and the transaction guarantees nothing sticks; perfect for quick debugging.
2. **Automatic cleanup** – no teardown code needed; the rollback wipes inserts, updates, temp tables, and even sequence increments.
3. **Deterministic, repeatable runs** – each execution starts from the same state, avoiding flaky tests caused by leftover data.
4. **Safety in shared dev databases** – parallel testers can run suites concurrently without clobbering each other’s data.

### When *not* to wrap

Some behaviours rely on a *real commit* and therefore **must run outside a manual transaction**:

* **Service Broker** – message delivery, queue activation, and conversation state changes happen only after the outer transaction commits.
* **SQL Agent jobs / sp\_start\_job** – the job fires in another session; holding a transaction open can delay or block its execution.
* **Commit‑driven features** – triggers that enqueue work to other systems, Change Data Capture, replication, Query Notifications.
* **Cross‑session concurrency tests** – scenarios where one connection must commit so another can observe locks or row versions.

In those cases, omit `BEGIN TRAN / ROLLBACK` and either:

* Run against disposable test data, or
* Add explicit cleanup at the end of the test.

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
    SELECT test.assert_equals('20 + 22 must be 42', 42, @result);
ROLLBACK;
```

### 2. Recordset comparison (no temp tables needed)

```sql
CREATE OR ALTER PROCEDURE [tests].[api.get_users@ordering]
AS
BEGIN TRAN
    /*
       Compare the JSON produced by the procedure directly with the expected
       literal – no @expected/@actual temp vars necessary because helpers are
       **functions**.
    */
    SELECT test.assert_equals(
        'Users must match',
        (
            SELECT *
            FROM (VALUES (1, N'Ann'), (2, N'Bob')) v(id, name)
            ORDER BY id
            FOR JSON PATH
        ),
        (SELECT * FROM dbo.get_users() ORDER BY id FOR JSON PATH)
    );
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
        SELECT test.assert_error(
            N'Invalid customer validation',
            50001, N'%invalid customer%', DEFAULT);
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

### 1. **Assertions as functions**

Most assertion helpers (`test.assert_equals`, `test.assert_error`, `test.fail`)
are **scalar functions**. The dynamic query helper `test.assert_resultset_equals` is a
stored procedure because functions cannot execute dynamic SQL.
Why this matters:

* You can embed assertions directly into `SELECT` lists or `WHERE` clauses.
* Functions accept *expressions* and *sub‑queries* as arguments. Example: pass an on‑the‑fly recordset as JSON without staging it in a temp table.
* Classic procedure‑style helpers (like in tSQLt) would force extra variables / temp objects.

```sql
SELECT test.assert_equals('Rows must match',
        (SELECT * FROM @expected FOR JSON PATH),
        (SELECT * FROM dbo.get_users() FOR JSON PATH));
```

### 2. **Throwing from a function**

SQL Server forbids `RAISERROR` / `THROW` inside scalar UDFs. T‑TEST sneaks around this rule with a type‑mismatch trick:

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

```sql
-- list all registered tests with their target objects and parsed metadata
SELECT *
FROM   test.test;
```

### 5. **Sentinel‑style exception testing**

A concise pattern for verifying that a call *does* raise the expected error and that the error’s properties are correct.

1. **Act** – run the statement expected to fail.
2. **Sentinel** - `EXEC test.fail_no_error;` immediately after; missing errors fail the test.
3. **Assert** - inside `CATCH` use `test.assert_error` with the required filters.

```sql
BEGIN TRY
    EXEC sales.usp_create_order @customer_id = -1;  -- (1) act
    EXEC test.fail_no_error;                       -- (2) sentinel
END TRY
BEGIN CATCH                                         -- (3) assert
    SELECT test.assert_error(
        N'Invalid customer validation', 50001, N'%invalid customer%', DEFAULT);
END CATCH;
```

`test.fail_no_error()` always raises the missing-error sentinel; place it directly
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
| `test.assert_equals(msg, expected, actual)`      | smart equality check (numbers, JSON, etc.)                     | `test.assert_equals('Should be 42', '42', @val)`                      |
| `test.assert_float_equals(msg, expected, actual, tolerance)` | FLOAT equality within an inclusive absolute tolerance | `test.assert_float_equals('Deviation', @expected, @actual, 1E-12)` |
| `test.assert_resultset_equals @message, @expected_query, @actual_query` | Compare two SELECT results; stored procedure | `EXEC test.assert_resultset_equals N'Rows', N'SELECT 1 AS id', N'SELECT 1 AS id';` |
| `test.assert_error(msg, expected_number, expected_message_pattern, expected_state)` | Match a caught error; NULL/DEFAULT skip individual filters | `test.assert_error(N'Expected message', DEFAULT, N'%Invalid customer%', DEFAULT)` |
| `test.assert_not_null(msg, value)`               | value **must** be NOT NULL                                     |                                                                       |
| `test.assert_null(msg, value)`                   | value **must** be NULL                                         |                                                                       |
| `test.fail(msg)`                                 | fail immediately, you can add your conditions in WHERE section | SELECT `test.fail('Not implemented')` WHERE IsAdmin(@my\_profile) = 0 |
| `test.fail_no_error()` | Fail when an expected exception did not occur; place after the tested call | `SET @result = test.fail_no_error();` |
|                                                  |                                                                |                                                                       |

`assert_float_equals` returns `N''` on success and raises an assertion failure on
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
`test.fail_no_error()` no-error sentinel, the assertion fails. Success returns NULL.
Scalar-function calls still supply all argument positions; use `DEFAULT` for
omitted filters.

```sql
DECLARE @result nvarchar(max), @error_result int;
BEGIN TRY
    SET @result = test.assert_float_equals(N'Different values', 1, 2, 1E-12);
    SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
    SET @error_result = test.assert_error(
        N'Different floats must fail', 245, DEFAULT, DEFAULT);
END CATCH;
```

---

## ⚙️ Runner options

```sql
EXEC test.run
      @test_names        = N'[tests].[sales.usp_create_order@happy_path]|[tests].[inventory.adjust_stock@edge_case]',
      @exclude_test_names = N'[tests].[sales.usp_create_order@obsolete]',
      @schemas            = N'sales,inventory',
      @exclude_schemas    = N'legacy',
      @limit_failed       = 5,              -- stop after 5 failures
      @before_callback    = N'SET NOCOUNT ON',
      @log_proc_name      = N'test.log';
```

| Parameter                       | Default      | Description                                                         |
| ------------------------------- | ------------ | ------------------------------------------------------------------- |
| `@test_names`                   | `NULL`       | Pipe‑separated list of fully‑qualified test procedures to *include* |
| `@exclude_test_names`           | `NULL`       | Pipe‑separated list to *exclude*                                    |
| `@schemas` / `@exclude_schemas` | `NULL`       | Filter by *tested object* schema (not test schema)                  |
| `@limit_failed`                 | `1 000 000`  | Fail‑fast after N failures                                          |
| `@before_callback`              | `NULL`       | T‑SQL executed before each test (e.g. `DBCC DROPCLEANBUFFERS`)      |
| `@log_proc_name`                | `'test.log'` | Plug‑in alternative logger                                          |

Name lists contain exact procedure names; `*` and other wildcard patterns are
not supported. Use `@schemas` and `@exclude_schemas` to filter by the tested
object's schema instead.

---

## 📝 Logging

`test.log` standardises messages (`DEBUG`, `INFO`, `WARNING`, `ERROR`). Pass contextual data via `%1..%4` placeholders:

```sql
EXEC test.log @message = 'Imported %1 rows', @p1 = @@ROWCOUNT, @severity = 'info';
```

Feel free to swap it with your own implementation and point `test.run` to it.

---

## 🤖 CI integration

Add a job after your migration step:

```yaml
- task: SqlAzureDacpacDeployment@1
  inputs:
    sqlFile: migrations.sql
    # …
- script: sqlcmd -b -S $(DbServer) -d $(Db) -i sql/run_tests.sql
  displayName: "Run T‑SQL unit tests"
```

* `-b` makes `sqlcmd` exit with non‑zero code on `THROW`, so the pipeline fails if tests fail.

---

## 🔄 T-TEST vs. tSQLt

| Area                                       | T-TEST                                                                                                                                                                                                                             | tSQLt                                                                                                                                                               | Take‑away                                                                                     |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| **Installation size**                      | single script, < 10 KB of objects in `test` & `tests` schemas                                                                                                                                                                      | \~700 KB, dozens of objects spread across multiple helper schemas (`tSQLt`, `tSQLtPrivate`, etc.)                                                                   | T-TEST is tiny & vendor‑free; tSQLt is feature‑rich but heavy                                 |
| **How recordsets are compared**            | `test.assert_equals` does *smart* binary/JSON/decimal equality – often one line                                                                                                                                                    | `tSQLt.AssertEqualsTable` requires creating an *expected* table variables                                                                                           | T-TEST is terser; tSQLt is explicit but verbose                                               |
| **Service Broker & SQL Agent job testing** | Works seamlessly: each test opens its own `BEGIN TRAN` so dialogs, job runs, messages happen inside the same transaction and are rolled back                                                                                       | Standard pattern uses `EXEC tSQLt.NewTestClass` which wraps an *outer* transaction; Service Broker & job threads run **outside** it, often making assertions tricky | T-TEST 🟢; tSQLt requires extra harness or disabling transactions                             |
| **Test classification**                    | Test procedure name encodes target: `[tests].[schema.object@scenario]` ⇒ quick filtering by schema/object                                                                                                                          | Uses *test classes* (schemas) + procedure name – extra level, but cleaner separation                                                                                | Depends on taste; tSQLt needs no helper commands to create classes                            |
| **Execution flexibility**                  | `test.run` accepts *include / exclude* lists, schema filters, fail‑fast limit, callback hook                                                                                                                                       | `EXEC tSQLt.Run` runs all or a single class; finer filtering requires PowerShell or wrapper scripts                                                                 | T-TEST offers more granular selection out‑of‑the‑box                                          |
| **Helpers & exception handling** | Helpers are **functions**, usable inline with expressions or scalar subqueries. `test.fail_no_error` guards missing exceptions; `test.assert_error` checks number, LIKE message and state. | Helpers are *procedures*. Need temp tables / variables for passing data; exception tests rely on `tSQLt.ExpectException` with hard-coded numbers. | Functions inline reduce boilerplate. tSQLt procedures support output capture but add ceremony. |
| **Mocking / Isolation**                    | Uses your own `BEGIN TRAN / ROLLBACK`; no automatic fake tables                                                                                                                                                                    | Rich mocking: fake tables, spy procedures, `tSQLt.FakeTable`, `tSQLt.SpyProcedure`                                                                                  | tSQLt wins for complex mocks                                                                  |
| **Dependencies**                           | None (pure T‑SQL)                                                                                                                                                                                                                  | CLR enabled (for NUnit‑style output) on older versions, external installer                                                                                          | T-TEST easier on locked‑down servers                                                          |

**When to prefer T-TEST**

* You want a *minimal* framework that piggybacks on plain T‑SQL and works in any environment (Azure SQL DB, managed instances, on‑prem).
* Your primary pain‑point is **assertion verbosity** rather than advanced mocking.
* You need to test **Service Broker conversations or SQL Agent jobs** inside the same transaction.

**When to stick to tSQLt**

* You rely on its **fake tables / spy procedures** for heavy isolation or mocking.
* You need its **code‑coverage hooks** or integration with existing tSQLt‑based test suites.

---

## 📄 License

[MIT](LICENSE)

---

## 🤝 Contributing

1. Fork / create a feature branch.
2. Add or update objects in `test` schema, add tests inside `tests` schema.
3. Ensure `EXEC test.run` passes.
4. Submit a PR.

Feel free to open issues for bugs or feature requests.

---
