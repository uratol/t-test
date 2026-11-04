# Research: static and parameterized tests

**Status:** vectors are implemented; dimensions remain a later-phase design.
Installation provisions permanent vector storage. Users create session tables and
choose scope via one optional `test.set_scope` call. It sets
`ttest:vectors:scope` in the current connection's session
context: **`N'global'` is the default**, using permanent storage. Select
`N'session'` explicitly for connection-local temporary registration tables.
`test.vector`, `test.dimension`, `test.run` and `test.reset` read that setting;
none gains a scope parameter. Session scope uses `#`; global scope uses none.
Vectors are complete SQL argument lists; dimensions are scalar JSON arrays parsed
once into SQL literals. Existing unregistered tests keep their behavior.
SQL Server 2022+ and Fabric Warehouse execution must both be verified.

## 1. Core model

Keep two execution forms and normalize both into individual test cases:

| Form | Definition | Execution |
| --- | --- | --- |
| Static | A test procedure without registered cases, including procedures with optional parameters. | One invocation without arguments, preserving current behavior. |
| Parameterized | A test procedure with explicit vectors, named dimensions, or both. | Two run-wide phases: explicit vectors for all selected procedures, then all dimension combinations. |

Procedures with parameters can be executed based on two sources:
- A case vector contains the arguments for one invocation. Explicit vectors follow
the procedure's declared parameter order: `1, N'a'` supplies `1` as the first
argument and `N'a'` as the second.
- Dimension-generated vectors associate values
with explicit parameter names and pass them as named arguments. Dimension
names control binding, not registration order. The minimal storage does not
promise registration order or JSON array order during execution.

The generator does not know which arguments describe inputs, expected results,
tolerances or other test settings. The test procedure owns those meanings.
An expected-result argument is an ordinary input parameter, not a SQL `OUTPUT`
parameter.

### Quick start for SQL test engineers

This example is for the future API, after implementation and installation.
Run it in a test database on one fresh connection, outside a transaction.
Use an unused procedure name and stop if any statement fails; cleanup must not
remove a pre-existing procedure. The name follows the
existing `object@action` convention without requiring a separate database object.
Run the same script unchanged on SQL Server and Fabric Warehouse.
A fresh connection defaults to global storage. This ad hoc example explicitly
selects session storage before creating temporary registration tables:

```sql
CREATE PROCEDURE [tests].[replicate@cases]
    @number int,
    @text nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected int = @number * LEN(@text);
    DECLARE @actual int = LEN(REPLICATE(@text, @number));
    DECLARE @result nvarchar(max);
    SET @result = test.assert_equals(N'Repeated text length', @expected, @actual);
END;
GO

EXEC test.set_scope N'session';

CREATE TABLE #test_vectors (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);

CREATE TABLE #test_dimension_values (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);

-- Correlated cases: register complete argument lists.
EXEC test.vector '[tests].[replicate@cases]', '1,''a''';
EXEC test.vector '[tests].[replicate@cases]', '2,''bb''';
EXEC test.run @test_names = N'[tests].[replicate@cases]';
-- Two invocations.

-- Independent domains: every number is combined with every text.
EXEC test.dimension '[tests].[replicate@cases]', '@number', '[1,2]';
EXEC test.dimension '[tests].[replicate@cases]', '@text', '["a","bb","ccc"]';

EXEC test.run @test_names = N'[tests].[replicate@cases]';
-- Eight invocations: the same two vectors, then six combinations.

EXEC test.reset;
DROP PROCEDURE [tests].[replicate@cases];
```

`test.reset` clears registrations, not procedures. A retained parameterized
procedure with required arguments must be registered again before an unfiltered
run; otherwise its argumentless invocation reports a normal SQL execution error.
Creating only the table for the source you use is sufficient. Keep both tables
for mixed registrations or repeated runs; reset does not drop them.

## 2. Two independent sources of test cases

Register complete positional vectors and named parameter domains independently:

| Registration | Author supplies | Runner does |
| --- | --- | --- |
| `test.vector` | One complete vector for a named procedure. | Executes that vector unchanged in the first phase. |
| `test.dimension` | Possible values for one named procedure parameter. | Executes each Cartesian-product vector in the second phase. |

Within the selected store, a procedure can have both sources. Neither replaces,
augments or filters the other's arguments. Finish the explicit-vector phase for all
selected procedures before starting the dimension-generated phase.

### Explicit vectors

Use vectors for correlated arguments: input/expected-output pairs, matching
customer/order identifiers or hand-selected regressions. Each row is a complete
invocation, as shown in the quick start. Preserve duplicate rows: two identical
registrations still request two invocations. The runner does not infer expectations.

### Dimensions: Cartesian-product generation

For `@number = [1,2]` and `@text = ["a","b","c"]`, the stored text literals
are `N'a'`, `N'b'` and `N'c'`. Their product has six cases. On the quick-start
procedure, these calls illustrate the combinations, not their execution order:

```sql
EXEC [tests].[replicate@cases] @number = 1, @text = N'a';
EXEC [tests].[replicate@cases] @number = 1, @text = N'b';
EXEC [tests].[replicate@cases] @number = 1, @text = N'c';
EXEC [tests].[replicate@cases] @number = 2, @text = N'a';
EXEC [tests].[replicate@cases] @number = 2, @text = N'b';
EXEC [tests].[replicate@cases] @number = 2, @text = N'c';
```

Every combination must be meaningful for the intended test. If an `@expected`
argument has several values, it is combined independently like any other
dimension; the generator does not derive the correct expectation.

### Additive execution

Two explicit vectors plus two domains containing two and three values produce
`2 + (2 * 3) = 8` invocations, not twelve. Explicit vectors are not another
dimension and are never combined with domain values.

Do not deduplicate across the two sources. If a generated vector matches an
explicit vector, both execute and produce separate results. Failures in the first
phase do not gate the second phase, except for existing run-abort conditions such
as a callback failure or the failure limit.

## 3. No parameter-type reconstruction

SQL owns argument counts, defaults and conversions. Do not reconstruct declared
types, parse procedure definitions or convert registered values to target types.
Use `sys.parameters` only for a name lookup when registering a dimension: resolve
the target's `object_id` and store the matching declared parameter name.
This avoids a custom identifier parser and inconsistent casing in stored domains.
Resolve names under the database identifier collation, before writing UTF-8 rows;
metadata visibility is required, as it already is for test discovery.

The author must keep vectors compatible with the signature. Wrong argument counts
and unsuccessful conversions are execution errors, not something the generator
repairs. An unknown dimension parameter is a registration error; if a signature
changes after registration, SQL can still reject the generated call at execution.
Omitted parameters use SQL defaults when available; the framework adds no values.

Explicit vectors already contain SQL literals, such as `42`, `1.25`, `N'text'`,
`NULL`, `0`, `1` or `0x0A`. Dimensions instead map JSON numbers, strings and null to
numeric literals, Unicode string literals and SQL `NULL`. This mapping depends
only on the JSON element type, never on a target parameter's declared SQL type.

Authors must supply SQL-compatible values: use numeric `0` and `1` for bit
parameters, not JSON `false` and `true`. Date/time and GUID values are JSON strings
whose text must support SQL's normal parameter conversion; use unambiguous date
formats. JSON does not support SQL hexadecimal literals or arbitrary expressions.
Use explicit vectors when an exact SQL literal such as `0x0A` is required.

Preserve explicit-vector spelling and dimension numeric text without a FLOAT
round trip. Do not turn SQL `NULL` into `N'NULL'` or silently replace bad values
with NULL through `TRY_CONVERT`. Invalid SQL syntax fails dynamic-batch compilation;
argument binding and conversions may fail when the procedure is invoked.

## 4. Invocation by SQL-literal concatenation

Build an explicit call from `EXEC`, the canonical quoted procedure name, a space,
the unchanged vector and a terminator. For `1, 'a'`:

```sql
EXEC [tests].[replicate@cases] 1, 'a';
```

Do not split, quote or reformat explicit vectors. 

For dimensions, parse JSON at registration, store SQL literals, 
then join domain rows and concatenate named
assignments without parsing JSON again:

```sql
EXEC [tests].[replicate@cases] @number = 1, @text = N'a';
```

Named arguments make registration order irrelevant. `OPENJSON` handles commas,
escaped quotes and backslashes; no tokenizer is needed. `"GETDATE()"` becomes
`N'GETDATE()'`, never code. `"NULL"` remains text; only JSON null becomes SQL NULL.

**Trust boundary:** explicit vectors remain trusted SQL test code, not arbitrary
external data. Dimension strings must always be emitted as quoted SQL literals,
never concatenated as code. Registration targets must be schema-qualified names
of discovered tests in the current database; reject database/server qualification.
Resolve to metadata and quote the canonical name, rather than appending the input
name. Dimension parameter names come from metadata, not arbitrary SQL fragments.
Use `sp_executesql` for registered invocations; keep the existing
`EXEC @full_proc_name` path for unregistered tests.

## 5. Registering definitions before test.run

### One switch, two storage choices

| `test.set_scope @scope` | Vector table | Dimension table | Lifetime and visibility |
| --- | --- | --- | --- |
| `N'session'` | `#test_vectors` | `#test_dimension_values` | Current connection only; automatically dropped when it closes. |
| `N'global'` (default) | `[test].[test_vectors]` | `[test].[test_dimension_values]` | Permanent, shared definitions in the current database; survive connection closure. |

**Global storage requires no scope call:** an unset context uses the permanent tables.
For session storage, call `EXEC test.set_scope N'session';` once on that connection.
The selected scope persists until changed and is independent of registration rows.
There is no automatic fallback, merge or copy between stores. On an unset
connection, `EXEC test.run;` reads global registrations only.
Accept only `N'session'` and `N'global'`, not NULL, blank values or table-name
prefixes. Resolve session scope to the `#` prefix and global scope to the permanent
names above; do not concatenate arbitrary input into SQL object names.
Global means shared permanent tables in this database, not `##` temporary tables
or a setting that changes other connections.
Store only the scope under `ttest:vectors:scope`, not a second prefix key.
Read an unset key as `global`. Switching scope neither clears registrations nor
creates tables. Reset deletes rows in the selected store but leaves scope unchanged.
On each new or reused logical connection, select the intended scope explicitly;
do not assume that a pooled connection retains a previous request's setting.

The switch chooses registration storage only. Private snapshots, queues and run
snapshots retain runner-owned, short-lived storage. No configuration ID, session
token, table-name parameter or storage-provider abstraction is needed.

Installation provisions the permanent vector table if missing, preserving any
existing compatible table and saved rows. Its definition and the future, caller-created
dimension table use the same columns as the temp tables:

```sql
IF OBJECT_ID(N'[test].[test_vectors]', N'U') IS NULL
    CREATE TABLE [test].[test_vectors] (
        procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
        parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
    );

CREATE TABLE [test].[test_dimension_values] (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);
```

With the example test procedure installed, register permanent cases once:

```sql
EXEC test.set_scope N'global';

EXEC test.vector
    N'[tests].[replicate@cases]', N'1,N''a''';
EXEC test.dimension
    N'[tests].[replicate@cases]', N'@number', N'[1,2]';
EXEC test.dimension
    N'[tests].[replicate@cases]', N'@text', N'["a","bb","ccc"]';
```

Any later connection can run those seven cases without recreating or registering
them again. The test procedure must remain installed; the quick start removes
its demo procedure, so recreate it before using this separate example.

```sql
EXEC test.set_scope N'global';
EXEC test.run @test_names = N'[tests].[replicate@cases]';
```

`EXEC test.reset;` clears only the currently selected store. In global scope it
deletes permanent registrations shared by all users. This is an explicit maintenance
operation, not a required step before running saved configurations.
To return to ad hoc registrations, call `EXEC test.set_scope N'session';`.

### Caller setup and actionable errors

Create session tables directly in the calling batch, not inside a procedure or
nested dynamic batch. Installation provisions the permanent vector table if absent;
permanent dimension storage remains caller-provisioned for the future phase.
Storage APIs know required column names and their meaning, not physical storage:
they use named-column INSERTs and reads, never create, alter or drop registration
tables. Users choose compatible types, indexes and other supported storage options;
extra columns need defaults or must permit NULL. Constraints must allow duplicate
case/value rows. The examples use identical ordinary DDL on both engines.
UTF-8 VARCHAR avoids unsupported persisted NVARCHAR columns on Fabric.
Inputs and local variables remain Unicode strings. The 2,048-byte procedure-name
column accommodates escaped identifiers and UTF-8 bytes; do not narrow names
through smaller intermediate variables. No registration identity is required.

Each registration procedure first checks for its required table:

| API | Required table in the selected store |
| --- | --- |
| `test.vector` | `#test_vectors` or `[test].[test_vectors]` |
| `test.dimension` | `#test_dimension_values` or `[test].[test_dimension_values]` |

A registration table not found by the existence probe is not a fatal error.
Vector/dimension print a warning naming the API, selected scope and missing table,
skip that registration call and return without writing rows. Include suggested
CREATE TABLE DDL for the user, shared by both engines. Do not initialize tables.
For temp tables, explain that setup must run directly on the same connection.
For permanent tables, explain that they must be provisioned in this database.
For example, the session-scope vector warning contains:

```text
WARNING: test.vector skipped in session scope: #test_vectors was not found.
Run this directly in the calling batch on the same connection before registration:
CREATE TABLE #test_vectors (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);
```

`test.dimension` reports its own suggested DDL; permanent-store errors show the
permanent name, never a temp-table workaround. These are setup templates, not a
requirement to match physical table options or types exactly.
Keep messages within SQL's message-length limit. The existence probe
must be verified on both engines; SQL Server can use
`OBJECT_ID('tempdb..#test_vectors')` for session storage and
`OBJECT_ID(N'[test].[test_vectors]', N'U')` for permanent storage.
Put selected-table reads and writes in a nested dynamic batch after the check, so
compilation of an absent table cannot bypass the useful warning. This also applies
to the runner and reset, which must tolerate absence.
Treat OBJECT_ID NULL as unavailable for this minimal design; do not add metadata
visibility or permission-diagnosis probes. The user investigates setup/permissions.
Native errors after a table passes the probe still propagate; do not suppress
unrelated INSERT, SELECT or conversion errors.

The runner treats an absent source table as unregistered within the selected
store; it never consults the other store. Creating only the source table you use
is sufficient. Runner and reset silently skip sources not found by the probe,
preserving static logger behavior. Missing registration data is not a failed test
case; the final summary describes only the cases actually available to that run,
not the user's intended configuration.

### Public signatures

```sql
test.set_scope
    @scope nvarchar(max)

test.vector
    @test_name nvarchar(max),
    @parameters nvarchar(max)

test.dimension
    @test_name nvarchar(max),
    @parameter_name nvarchar(max),
    @values nvarchar(max)

test.reset

test.run
    @test_names nvarchar(max) = NULL,
    @exclude_test_names nvarchar(max) = NULL,
    @schemas nvarchar(256) = NULL,
    @exclude_schemas nvarchar(256) = NULL,
    @limit_failed int = NULL,
    @before_callback nvarchar(max) = NULL,
    @log_proc_name nvarchar(256) = NULL
```

These are signatures, not executable declarations. Setter and registration inputs
are required. The seven-argument `test.run` signature remains exactly unchanged,
and reset has no arguments. MAX inputs permit validation before truncation.
Dimension names include `@`. All storage APIs read scope once at entry; the runner
captures it before snapshotting. A callback changing session scope affects later
API calls, never the active run's selected tables or frozen cases.

### Explicit SQL vectors and JSON dimension escaping

Use Unicode `N'...'` registration strings and leave `QUOTED_IDENTIFIER` unchanged.
For explicit vectors, double apostrophes for the outer T-SQL literal:

```sql
EXEC test.vector
    N'[tests].[example.text]',
    N'N''O''''Brien, Jr.'', NULL, 0x0A';
```

For an illustrative three-argument procedure, this generates:

```sql
EXEC [tests].[example.text] N'O''Brien, Jr.', NULL, 0x0A;
```

For dimensions, use JSON values instead of writing SQL literal syntax:

```sql
EXEC test.dimension
    N'[tests].[example.text]',
    N'@text',
    N'["O''Brien, Jr.","",null,"NULL","GETDATE()"]';
```

The five stored literals are `N'O''Brien, Jr.'`, `N''`, `NULL`, `N'NULL'` and
`N'GETDATE()'`. The apostrophe in `O''Brien` is doubled only for the outer T-SQL
string; JSON itself does not require escaping apostrophes. Inside JSON strings,
double quotes, backslashes and control characters follow JSON escaping rules.
For example, `N'["a\"b","c\\d","line\nbreak"]'` defines three string values.

Prefix SQL text literals inside explicit vectors with `N` when Unicode is needed.
The outer Unicode literal alone does not change the stored inner literal's type.

### JSON dimension contract and registration algorithm

Supply one nonempty JSON array of numbers, strings and null. Booleans (`true`,
`false`), objects and nested arrays are unsupported; the author must not supply
them. Do not add explicit element-type checks or custom rejection messages.
`[null]` is a valid one-value domain.

| OPENJSON type | Input example | Stored SQL literal |
| --- | --- | --- |
| `0`, null | `null` | `NULL` |
| `1`, string | `"a,b"` | `N'a,b'` |
| `1`, string | `"O'Brien"` | `N'O''Brien'` |
| `1`, string | `""` | `N''` |
| `1`, string | `"GETDATE()"` | `N'GETDATE()'` |
| `2`, number | `1.2500` | `1.2500` |
| `3`, boolean | `true` or `false` | Unsupported; do not supply. |
| `4` or `5` | Nested array or object | Unsupported; do not supply. |

Implement registration as a parse-and-insert pipeline:

1. Reject SQL NULL, validate syntax with single-argument `ISJSON`, then require
   the first non-JSON-whitespace character to be `[`. Handle spaces, tabs,
   carriage returns and newlines, not just ordinary spaces. Use this same path
   on both engines instead of adding a version-dependent validation branch.
2. Resolve the target and declared parameter name; reject an already registered
   domain in the captured store before writing.
3. Use default-schema `OPENJSON(@values)` directly in the INSERT. Keep `[type]`
   and MAX-length `[value]`; do not narrow through JSON_VALUE or numeric WITH types.
4. Preserve every element, including duplicates. Array indexes need not be stored:
   execution order is not part of this minimal contract.
5. Convert OPENJSON values into SQL literals and insert all domain rows with the
   canonical procedure and parameter names in one atomic INSERT.
   A failed INSERT must not leave a partial domain or damage existing registrations.
   To change a domain, reset that store and register again; there is no replacement
   path. Carry the selected scope through the INSERT and duplicate-domain check.

The direct INSERT projects these literals from OPENJSON:

```sql
SELECT
    CASE [type]
        WHEN 0 THEN CAST(N'NULL' AS nvarchar(max))
        WHEN 1 THEN
            N'N' + NCHAR(39)
            + REPLACE(CONVERT(nvarchar(max), [value]),
                NCHAR(39), NCHAR(39) + NCHAR(39))
            + NCHAR(39)
        WHEN 2 THEN [value]
    END AS value
FROM OPENJSON(@values);
```

Keep this CASE limited to supported types, without an extra validation pass.
An unsupported type has no matching branch; the existing NOT NULL storage
constraint can raise a native SQL error. Do not add special handling for it.
Keep values MAX-typed so replacement and concatenation preserve long strings.
No registration staging table or second JSON encoding is needed. Capture the
INSERT's @@ROWCOUNT immediately in the dynamic batch; zero rows means an empty
domain and raises a definition error without modifying existing registrations.
SQL-unrepresentable string contents must raise a visible error, never be removed
or replaced silently; control-character examples cover tabs and CR/LF.

Numeric values remain the text returned by `OPENJSON`, without conversion through
FLOAT, MONEY or a fixed DECIMAL type. Valid JSON does not guarantee that a number
fits SQL's numeric literal limits or the target parameter: SQL reports those
errors when invoking the generated call. JSON strings are already decoded;
quote their actual contents once for SQL, not their original JSON escape spelling.

### Configuration lifecycle

| Call or condition | Required behavior |
| --- | --- |
| Caller setup | Installation provisions the permanent vector table if absent. Create temp tables in the calling batch; future permanent dimension tables remain caller-provisioned. |
| `test.set_scope` | Store session/global in the current connection's context; change no table or registration rows. |
| Registration without its table | Print a warning with suggested DDL, skip that call and continue without rows. |
| `test.vector` | Append one positional case to the named procedure, preserving its dimensions. |
| `test.dimension` | Register a new domain; reject a second registration of the same procedure/parameter without changing existing rows. |
| Registering another procedure | Preserve all registrations for other procedures. |
| `test.run` | Snapshot only the selected store; execute explicit cases first, then dimension combinations, without consuming configuration. |
| `test.reset` | Delete all rows from whichever registration tables exist in the selected store; keep definitions and leave the other store untouched. |
| Connection closes | Session tables and scope selection disappear; permanent tables and their rows remain. A fresh connection defaults to global. |
| Neither source registered for a selected test | Invoke it once without arguments, preserving current behavior. |

Discovery and filters decide which procedures execute; registrations do not bypass
them. Unconfigured procedures use SQL's normal defaults or missing-argument errors.

Malformed registrations fail the registration call without changing its stored
rows. A configuration error found in selected registrations during run preflight
aborts that run before any callback or test; excluded procedures do not block it.
Do not silently substitute static execution for malformed configuration.
Repeated runs reuse registrations. Freeze selected registrations before the first
callback so registration or reset inside a test cannot change the active run.
Use public registration calls to produce canonical names and SQL literals.
Incompatible columns or manually supplied noncanonical rows are outside the
contract; do not add a schema migration or general table-repair layer.

### Caller-owned storage

Both stores have the same logical shape: one argument list per vector row, one
SQL literal per dimension-value row. Storage does not add session IDs or columns.
Installer creates the permanent vector table if absent and preserves existing
compatible tables and saved rows. Uninstaller and storage APIs never create or drop
registration tables; future dimension storage remains caller-provisioned.
Uninstall must preserve saved configurations; users remove their tables themselves.
Execute storage operations as the caller, with their normal SELECT/INSERT/DELETE
permissions; do not impersonate an owner to grant access to permanent definitions.
Store canonical procedure/parameter names resolved under database identifier
rules. In a case-insensitive database, `@Number` and
`@number` must not become two domains; respect distinct names in case-sensitive
databases. Stored group keys are not unique row IDs: duplicates remain valid.
Compare canonical stored keys with an explicit binary collation in reads and
duplicate-domain checks. A user-selected table collation must not merge distinct
procedures or parameters in a case-sensitive database.

Store `value` as non-NULL text: the SQL-null value is the string `NULL`, never
a database NULL in this column. Otherwise concatenation could silently omit an
argument. Do not deduplicate literal rows with `DISTINCT`.

### Selecting explicit vectors and joining dimensions

Read selected-store rows by canonical procedure name. Never merge temp and permanent
registrations. To avoid coupling permanent Warehouse tables to local temp tables,
capture selected rows into scalar JSON variables in a storage-only dynamic query,
then populate private snapshots from OPENJSON in a separate statement.
Use this same read path for either scope, not engine-specific copy branches.
Transport the stored names and SQL literals as JSON strings without reinterpreting
them; this is snapshot transport, not persisted JSON or another parse of the original
dimension arrays. Keep MAX-length text throughout.

Generate and execute cases only from private snapshots. For two dimensions, this
filtered product uses a runner-owned snapshot with the dimension table's columns:

```sql
SELECT
    CONCAT(
        CAST(N'' AS nvarchar(max)),
        N'@number = ', n.value,
        N', @text = ', t.value
    ) AS parameters
FROM (
    SELECT value
    FROM #test_run_dimension_values
    WHERE procedure_name = @procedure_name
      AND parameter_name = N'@number'
) AS n
CROSS JOIN (
    SELECT value
    FROM #test_run_dimension_values
    WHERE procedure_name = @procedure_name
      AND parameter_name = N'@text'
) AS t;
```

This returns six rows such as `@number = 1, @text = N'a'`; each is a complete
named argument list ready to append to `EXEC`. The MAX-typed concatenation avoids
an accidental short-string result limit.

For arbitrary dimensions, enumerate distinct registered names and generate one
alias per name. One domain needs a SELECT; each additional domain adds CROSS JOIN.
Use generated aliases such as `d1`, not user-supplied names. Pass procedure and
parameter filters as `sp_executesql` parameters; concatenate only trusted structure.

Filter every alias by procedure and parameter, not only the first alias. Mixing
another procedure's values into the product is never valid, regardless of storage.

### Lifetime, sharing and private work tables

Session tables isolate registrations by connection. Permanent definitions are
shared by all callers with access in the database; no per-user partitioning is
implied. Register permanent cases once, then run them from later connections.
Repeated vector registration still appends duplicates; it is not an upsert.
Repeated dimension registration still requires an explicit reset first.

Provision and modify permanent definitions without concurrent writers or readers
that require the old definitions. In particular, keep them unchanged while a run
copies its selected sources. The snapshot freezes data before callbacks, but is
not a transactional snapshot across the two permanent tables. This minimal design
adds no writer coordination, locks, versioning or configuration IDs. Concurrent
read-only runs are allowed; do not reset or edit their common registry during
snapshotting. A run that has already copied its data uses its private snapshot.

Use ordinary local temp tables for private snapshots and the case
queue on both engines, independent of registration storage. Create them directly
in their owning procedure before nested batches populate or read them. Do not
add engine-selected DDL, table options or dynamic table creation.
Drop only private tables created by the current call on success and handled error;
never drop caller registration tables or reuse their names for work tables.
Cleanup must preserve the original error.
Keep each storage statement confined to its resolved tables, parameters and
scalar expressions. Do not join permanent Warehouse tables or system catalog
views to private temp tables. Read rows through scalar JSON transport and resolve
metadata separately. Dimension INSERTs read OPENJSON directly from the input
parameter, without a staging table. Explicit vectors need scalar INSERT parameters.
This keeps storage-specific identifiers in small statements, not two runners.
Verify both storage paths and their OPENJSON operations on both engines.

Use explicit UTF-8 collation before narrowing Unicode to VARCHAR; do not convert
through the database's non-UTF-8 code page first. Convert stored UTF-8 literals
back to NVARCHAR(MAX) before building Unicode dynamic SQL. Verify text-size limits
for both permanent storage and private/default temp tables on both engines;
persisted Warehouse limits alone do not establish default temp-table limits.
Reject oversized text before insertion, including escaped SQL literals, instead
of promising unlimited values.
These are engine limits, not a configurable case-count cap.

On SQL Server, a temp table created inside a procedure disappears when it returns;
a setup procedure or `IF NOT EXISTS` does not fix that lifetime. Only session
setup therefore needs the outer batch. Select permanent objects from the current
database, and use one test database per connection while temp registrations exist.
Cross-database configuration remains outside scope.

## 6. Two execution phases, one case lifecycle

```text
Discovery and filtering
  -> resolve scope, snapshot selected registrations and check count overflow
  -> phase 1: execute registered explicit vectors for all selected procedures
  -> phase 2: generate and execute dimension combinations for all selected procedures
  -> aggregate reporting

Every registered case in either phase:
  -> callback -> Start exec -> invocation -> outcome handling -> result -> Completed exec

Unregistered static cases retain their existing callback, invocation and logging.
```

Do not execute the dimension cases of the first procedure while explicit cases
remain for another selected procedure. A selected procedure with neither source
registered executes once without arguments during the first pass. A procedure with
either source registered does not receive an extra argumentless invocation.

A static test can be represented internally with no argument text and
the same invocation lifecycle. For a procedure with valid registrations, `V`
explicit vectors and `D` dimension combinations give `V + D` planned invocations.
When no dimensions are registered, `D` is zero, not one empty-product invocation.
Only a procedure with neither source registered uses the single static invocation.

Use the relational CROSS JOIN query to generate dimension cases. A simple execution
bridge is a runner-owned `#case_queue(work_no, parameters)` work table. Create it
inside `test.run` before the nested dynamic batch, then populate it with a generated
`INSERT ... SELECT`. An internal BIGINT `ROW_NUMBER` supplies a queue index so
duplicate rows execute individually. Because the queue is reused, also increment
one run-local BIGINT invocation counter for each attempted call. Store that counter
and the original selection-entry index with the result, not in registration rows.
Neither is a stable public ID or an execution-order promise.

Materialize only one procedure's dimension product at a time, then clear the work
table before generating the next procedure. Queue only the current procedure's
explicit vectors when processing the first phase. This favors a straightforward,
row-based execution queue over dynamically generated nested loops.

There is no fixed case-count limit and no new limit parameter. Before the first
callback or test, compute counts with `COUNT_BIG` and checked BIGINT arithmetic.
Before multiplying positive counts `product * count`, reject
`product > 9223372036854775807 / count`; check additions with
`total > 9223372036854775807 - count`. Apply this to per-procedure products,
explicit-plus-generated counts and the run total. Overflow is a configuration
error, not a wrapped negative count or a truncated queue.
Keep parameterized summary counters and summed durations BIGINT too; do not narrow
them back to the current runner's INT aggregates.

No fixed cap does not mean bounded cost: five domains of twenty values already
produce 3,200,000 cases. Materialization can exhaust resources before any case of
that procedure runs. Keep one procedure's queue at a time; paging and streaming
are outside this minimal design. Infrastructure errors abort the run, not mark
unattempted cases as failed. `@limit_failed` counts observed failures across both
phases; it is not a generation, memory or runtime limit.

## 7. Required changes to the current runner

The current `test.run` invokes `exec @full_proc_name` without arguments and rejects
duplicate results by procedure name. Repeating the same procedure therefore needs
more than a new invocation statement.

| Current behavior | Parameterized requirement |
| --- | --- |
| One result per procedure name. | Registered cases have one result per invocation; duplicate-selection errors remain separate. |
| Callback before each procedure invocation. | Callback before each case, including static cases. |
| Failure details identify the procedure. | Registered-case labels add parameters to the static-style name; logs retain source and the complete call. |
| Summary counts procedure invocations as tests. | For runs using registrations, distinguish selected procedures, planned cases and executed cases. |
| Result rows join discovery by procedure name. | Parameterized-run reporting reads captured metadata from results, not a live discovery INNER JOIN. |

Preserve existing assertion-failure detection, unexpected-error handling,
transaction cleanup and refusal to start inside an existing transaction.
Callbacks still abort on failure. Retain PASS, assertion failure and unexpected
error internally. Conversion errors are unexpected errors, even when their number
is 245; preserve the existing failure-marker checks, not just the error number.

Two kinds of repetition must not be confused. Several registered vectors for one
selection entry are valid, including identical vectors. Repeating that procedure
in `@test_names` retains the existing duplicate-selection behavior and error.
Keep the discovery/filter result's multiplicity; do not silently use DISTINCT,
move the legacy error to preflight or remove the check globally.
At the existing result-write point, distinguish earlier results from the same
selection entry from results belonging to another entry for that procedure.
Both execution phases reuse the same selection-entry index. Preserve the existing
static duplicate scenarios, including their invocation counts before the error.

Keep the current JSON results accumulator; do not introduce a second reporting
store or persist public IDs. Extend each internal result with invocation number,
selection-entry index, source and MAX-length call text. The execution queue uses
rows, but this does not require replacing existing JSON discovery or reporting.
For a run with registrations, capture each selected procedure's display name and
main schema before callbacks, alongside the original selection entry. Write those
fields into each result, including static cases in a mixed run. Final detail and
schema grids read these result fields directly; they must not lose an attempted
case because a live discovery join no longer finds its procedure. No metadata
change detection or reconciliation is required. Preserve the legacy reporting
path when the entire run is unregistered.

### Per-invocation logging and failure reporting

Build the complete executable call once, including the procedure name and literal
arguments. For registered cases, log `Start exec` immediately before execution
and `Completed exec` after return or a caught test failure. Both carry the same
call text, source and run-local invocation number; completion includes the outcome.
Do not add these events to unregistered static cases: their logger calls and
messages remain unchanged, including in a mixed run.

```text
Start exec source=dimension invocation=3
EXEC [tests].[replicate@cases] @number = 1, @text = N'a';
Completed exec source=dimension invocation=3 PASS
EXEC [tests].[replicate@cases] @number = 1, @text = N'a';
```

`Completed` means the attempt finished, not that it passed. On assertion failure
or unexpected error, use `FAILED` or `ERROR` respectively and include the message.
Do not emit a successful completion for an unexecuted case. Callback failures
before invocation remain setup failures, not failures caused by that test call.
Framework/logger failures also abort; no matching completion is promised after
such an abort or connection interruption. Keep new logging outside the invocation
TRY/CATCH so a logger error cannot become a test failure or duplicate result.
For a caught registered-case failure, record and complete that case before honoring
`@limit_failed`; stopping must not omit its completion or start another case.

Store exact call text as MAX-length text with the result. Pass it through the
existing logger's `@data`, which prints long data in chunks, not through
`@p1_str` or a formatted short `@message`. Those routes truncate text.
Use the existing logger signature, including custom `@log_proc_name`; a custom
logger must retain `@data` if it needs complete calls.
Failure logs and internal result records identify the call, not merely the procedure:

```text
FAILED source=dimension
Call: EXEC [tests].[replicate@cases] @number = 1, @text = N'a';
Message: <original assertion failure message>
```

The final thrown exception is length-limited. Give it a concise failure summary;
the complete call and original available error message remain in internal result records and
the default logger's data output. Do not promise full replay text in THROW.
Preserve literal spelling; never rebuild arguments from converted target values.

Keep both existing result grids and their column order. The first remains
`test`, `duration, s`, `status`, `failure_reason`; do not add mandatory columns.
Unregistered rows keep the current test name and failure text. For registered
rows, display the static-style name and unchanged parameters in parentheses in
the MAX-length `test` value, for example `power@vectors (-2,3,-8)`;
failure reasons retain the assertion/error prefix and original message.
Identical registered calls may produce identical display labels and still remain
separate rows. Internal invocation numbers distinguish their logging events.
If no selected procedure has registrations, retain the existing output metadata,
summary text and logger behavior. Parameterized runs report selected procedure
count (distinct names), planned case count and attempted case count; planned
counts retain selection multiplicity. Schema durations sum only attempted calls.
Never describe skipped cases as successful.

## 8. Ordering, replay and validation

The global explicit-before-dimension phase order is guaranteed; order within a
phase is not. No vector, dimension, value or session IDs are part of registration.
Tests must not depend on execution order. Adding ordering columns later would be
a separate feature, not an implicit property of SQL table insertion.

Record `explicit`, `dimension` or `static` and the complete call with each result.
Replay is a manual EXEC on the same database with any required fixtures; the
framework does not recreate transaction, callback or data state.
Validate sources independently: explicit vectors need not appear in the product.
Do not split/count explicit arguments; SQL validates them during invocation.

Reject empty JSON arrays and SQL NULL or whitespace-only explicit vectors.
Whitespace here includes spaces, tabs, carriage returns and newlines; preserve
the original text after checking it. SQL text `NULL` and `N''` are valid vectors,
not empty configuration. Absence of both sources alone triggers static fallback.
Use registration/preflight errors as defined in section 5; SQL compilation,
argument binding and conversions inside an attempted call remain case errors.

## 9. Minimal implementation and strict review gates

The direction is static compatibility plus independent explicit vectors and
Cartesian-product dimensions, sharing one case lifecycle. Range and sequential
generation are outside the initial scope; neither adds API parameters or
implementation requirements.

Implement four small procedures: set_scope, vector, dimension and reset. Extend
the runner's scheduling, invocation and result handling without changing its
signature. Read scope from session context once per API call and resolve it to
known table names; do not introduce a storage-provider layer.
Keep one invocation lifecycle, the existing assertions, discovery view and logger.
Add the four procedure files
to SSDT and the shared installer; update uninstall and the API documentation.
Do not convert shipped tests or add parameterized examples to installation's basic
selection. Preserve the fourteen static checks and add POWER as the fifteenth
built-in procedure, using four vectors for eighteen installation cases in total.
Retain the existing optional packages.

There are no new runner arguments or repeated scope parameters. The design has no
fixed case cap, dimension replacement, per-test reset, public case IDs or replay
API. Captured SQL supports manual replay. It adds no SQL OUTPUT collection,
pairwise generation, randomization, expression
evaluation or automatic expected-result calculation. Whole vectors remain trusted
SQL argument-list text, not a parser for arbitrary SQL expressions.

Strict acceptance gates:

| Area | Required evidence before claiming support |
| --- | --- |
| Static compatibility | An unset context defaults to global. Without selected registrations, static execution remains unchanged. The runner's seven parameters stay unchanged. Existing basic tests and 49 framework scenario groups retain their outcomes, duplicate-selection counts, callback/logger behavior, failure-limit semantics and result grids. |
| Cases and phases | The quick start runs 2, then 8 cases; the two-by-three product has six combinations. Preserve duplicate values/vectors across sources, interleaved registrations, global phase order and named binding independent of registration order. |
| Registration behavior | Missing tables warn and skip registration; runner/reset continue without that source and never fall back to the other store. Invalid scopes, NULL/blank vectors, invalid JSON roots, empty arrays and repeated domains remain errors. Names respect database case sensitivity. No permission-diagnosis or custom element-type rejection is required. |
| Text fidelity | Round-trip Unicode, apostrophes, commas, quotes, backslashes, control characters, empty strings and values over 4,000 characters. Distinguish null from `"NULL"` and keep `"GETDATE()"` as text. Preserve numeric spelling/exponents and explicit binary literals. Check UTF-8 byte limits after escaping. |
| Lifetime and isolation | Temp registrations isolate connections and disappear on close. Permanent registrations survive connection closure and are readable from a second connection without re-registration. Reset affects only the selected store; permanent reset is shared. Private snapshots survive later registry changes and remain isolated between runs. |
| Storage ownership | Only test.set_scope takes a scope parameter. The session key persists across calls in one connection; global selects permanent names, never ## tables. Setter changes no rows; reset leaves the key unchanged. Verify connection isolation, repeated switching, invalid state and callback scope changes without changing the active snapshot. Uninstall preserves permanent definitions. |
| Execution and reporting | Missing required arguments, syntax/conversion errors, assertion failures and transaction cleanup are classified correctly. Check per-case callbacks, cross-phase failure limits, exact long calls through `@data`, distinct invocation events and no fake completion after logger failure. |
| Work planning | Check BIGINT multiplication and addition at their boundaries without materializing huge products. Confirm one procedure queue at a time and no hidden fixed cap. Infrastructure errors never create successful or failed results for unattempted cases. |

The same scripts for each storage choice must run unchanged on both engines.
Fabric runtime gates cover ordinary permanent tables and default temp tables:
existence checks, session-context setter/readback, scalar JSON transport, direct
OPENJSON INSERTs, temp-to-temp
products, metadata isolation, text-size limits, Unicode conversions and visibility
of procedure-created tables to nested batches.
If an operation fails there, revise it within the shared SQL surface rather than
introducing platform-specific DDL. The documented design is not runtime
verification; SQL Server checks alone do not prove Fabric Warehouse support.

## Implementation guidelines

This section defines implementation steps, not a second API. Examples are fragments
for the future procedure bodies; they do not install the feature.

### 1. test.set_scope: one session key

`test.set_scope @scope` accepts exactly `session` or `global`, without trimming or
silently truncating inputs. Validate before writing so an invalid call preserves
the previous setting. Store a bounded Unicode value: `sp_set_session_context`
accepts SQL_VARIANT, not NVARCHAR(MAX). Keep the key mutable to allow switching:

```sql
-- After validating the full @scope input:
DECLARE @stored_scope nvarchar(7) = CONVERT(nvarchar(7), @scope);
EXEC sys.sp_set_session_context
    @key = N'ttest:vectors:scope',
    @value = @stored_scope,
    @read_only = 0;
```

Use a binary comparison and an exact byte-length check for the two allowed strings;
SQL equality alone can accept trailing spaces. Do not store both scope and prefix.
Setter returns no result grid and does not check/create tables or delete rows.

At entry to vector, dimension, reset and run, copy context to a local variable:

```sql
DECLARE @scope nvarchar(4000) =
    CONVERT(nvarchar(4000), SESSION_CONTEXT(N'ttest:vectors:scope'));
IF @scope IS NULL SET @scope = N'global';
```

Validate the copied state before use, because callers can write session context
directly. Unsupported values or conversion errors must not fall back to session.
Use two fixed table-name variables selected from the four known names; no user
name fragments. Read SESSION_CONTEXT in scalar assignments, not distributed query
plans. This small entry sequence may repeat internally; public parameters do not.
No new helper function or general configuration manager is required.

The runner never reads the context again after entry. A callback can change it for
later calls, but the active runner uses its captured names and private snapshots.
`test.reset` does not restore session scope; switching back requires the setter.
Connection-local scope selection is not a database-wide option, even for global
storage. Use sequential calls on one connection, not concurrent MARS setters.

### 2. Registration: scalar inputs and one INSERT

For `test.vector`:

1. Capture scope and the vector table name. If OBJECT_ID returns NULL, print
   warning/DDL guidance and return without inserting. Do not distinguish absence
   from metadata invisibility or select another store. The user diagnoses setup.
2. Resolve the two-part procedure name through discovery to its canonical quoted
   name. Reject NULL/blank vector text; preserve accepted text unchanged.
3. Execute one parameterized, named-column INSERT into the resolved table:

```sql
-- @vector_table is one fixed trusted name; data stays parameterized.
SET @sql = N'INSERT ' + @vector_table
    + N' (procedure_name, parameters) VALUES (@name, @vector);';
EXEC sys.sp_executesql @sql,
    N'@name nvarchar(max), @vector nvarchar(max)',
    @name = @canonical_name, @vector = @parameters;
```

Apply the required Unicode/UTF-8 conversion before VARCHAR insertion as described
in section 5. Do not parse the vector, count its arguments, deduplicate or upsert.

For `test.dimension`, a table not found by the probe warns and returns before
data checks. Otherwise resolve the canonical procedure and declared parameter
name, validate the array root and check for an existing domain. Empty arrays are
checked only using the INSERT rowcount. Use one dynamic INSERT with scalar
parameters and the CASE mapping in section 5:

```sql
INSERT <resolved_dimension_table> (procedure_name, parameter_name, value)
SELECT @name, @parameter, <CASE mapping from section 5>
FROM OPENJSON(@values);
SET @inserted = @@ROWCOUNT;
```

The placeholders above are trusted structure assembled by the implementation,
not executable SQL as printed. Return `@inserted int OUTPUT` from sp_executesql.
If zero, raise the empty-domain error. A native INSERT error propagates unchanged;
no partial domain remains. Do not catch errors to substitute SQL NULL or add
special boolean/object checks. No staging table is needed. Permanent writers are
serialized by the provisioning workflow, not a new framework lock protocol.

### 3. test.reset: delete data, retain selection and tables

Capture scope once. For each table found by the probe, execute
`DELETE FROM <resolved_name>`. A NULL probe is a no-op without permission
diagnosis; a native DELETE error propagates. Do not use DROP, TRUNCATE, clear
SESSION_CONTEXT or touch the other store.
Two deletes are not promised to be an atomic pair: a failed second delete is
visible and the user can retry. This avoids introducing transaction ownership or
savepoint logic solely for reset. Global reset is shared maintenance.

### 4. test.run: preserve discovery and freeze registrations

Keep the exact seven-argument signature and the existing refusal to enter inside
a transaction. Preserve discovery JSON, filters, metadata visibility assumptions
and selection multiplicity. Classification is by registered rows, not by whether
the procedure happens to declare parameters.

Capture scope once. Before the first callback, copy selected registrations into
two private snapshots. Create these temp tables directly in runner scope with
UTF-8 text columns matching the registration shape. Capture each selected
procedure's rows through a storage-only dynamic query into NVARCHAR(MAX) JSON,
then INSERT snapshot rows from OPENJSON in a separate statement. For example:

```sql
SELECT @rows = CONCAT(N'[',
    STRING_AGG(CONVERT(nvarchar(max),
        JSON_OBJECT('parameters': parameters)), N','), N']')
FROM <resolved_vector_table>
WHERE procedure_name COLLATE Latin1_General_100_BIN2_UTF8 =
    @name COLLATE Latin1_General_100_BIN2_UTF8;
```

Pass `@rows nvarchar(max) OUTPUT` through sp_executesql. Insert it into the private
vector snapshot using OPENJSON WITH `(parameters nvarchar(max))` and the captured
canonical name. The dimension query also serializes parameter_name and value.
This uses existing JSON_OBJECT/STRING_AGG patterns, without nested FOR JSON,
system/data joins, narrowed JSON_VALUE extraction or reparsing dimension inputs.
Copy registrations once per distinct selected procedure, but retain the original
selection-entry list separately; duplicate selection must not multiply snapshots.
Capture display/schema metadata with selection entries for reporting as described
in section 7; do not join parameterized-run results back to live discovery.
Freeze all selected procedures before execution, not just the current procedure.
Skip source tables not found by the probe and leave their snapshots empty.

If no selected registrations exist, retain the static loop and output behavior.
Otherwise compute per-procedure and run-wide counts with checked BIGINT arithmetic,
then use one private `#case_queue(work_no bigint, parameters varchar(max))` with
UTF-8 collation. The queue is cleared between procedures; it is not the results
store. An internal ROW_NUMBER provides dense work numbers starting at one.

### 5. Scheduling and the common invocation lifecycle

Pass 1 walks the original selected list: queue explicit vectors for each procedure,
or its single argumentless case only if neither source exists. Pass 2 walks the
same list for dimension products. Both passes share callback, timing, invocation,
classification, rollback and result-writing logic; do not duplicate that body.
Use a phase variable in the enclosing loop rather than two copies of the runner.

For arbitrary dimensions, enumerate canonical parameter names into a local JSON
list. Generate aliases `d1`, `d2`, etc. For each alias, filter the private dimension
snapshot by the captured procedure and that parameter; cross-join those filtered
sets. Emit named assignments from the literal rows. Use parameters for procedure
filters and safely quoted name literals for generated fixed parameter filters;
never append unvalidated registration-name input as SQL structure.
A binary-stable parameter-name order is convenient for reproducible call text;
it does not promise case execution order. Seed concatenation with MAX text.

Insert one complete argument list per product row into the queue. Zero dimensions
means no generated cases, not an extra empty-product case. Preserve duplicates.
Select queue rows by work_no and build the full `EXEC` once per attempted case.
Registered cases use sp_executesql inside the invocation TRY/CATCH; unregistered
cases retain `EXEC @full_proc_name`. Syntax/binding errors from the nested batch
are caught as case errors. Invocation numbers are run-local, separate from work_no.

At the existing result-write point, the duplicate-selection predicate is:
`test_name = @full_proc_name AND selection_entry_index <> @selection_entry_index`.
Repeated cases of the same entry are allowed; another selection entry for that
procedure retains the legacy error. Both phases reuse the entry's original index.
Keep that check in the success and error paths rather than silently deduplicating.

Record outcome before logging completion, then honor the failure limit across both
phases. Keep Start/Completed logging outside the invocation TRY/CATCH, send full
call text through @data, and never record a logger failure as a test failure.
Use the existing JSON result accumulator with the added case fields. Its growing
MAX string can itself exhaust resources; no fixed case cap does not imply cheap
or unlimited reporting. Aggregate only attempted cases and preserve static grids.
For runs with registrations, project detail rows directly from result JSON and
group schema durations by the captured schema field. Grid rows and summary counts
must agree even when procedures change; do not monitor or reconcile those changes.
Drop only runner-owned work tables on return/handled abort without masking errors.

### 6. Delivery and focused verification

Add four SSDT procedure files and shared-installer definitions; update uninstall
to remove those four APIs but preserve user registration tables. Do not modify
assertions or move existing basic tests to parameterized registration. Installation
also provisions the global vector table if absent. Verification selects session scope,
restores the original context on success/failure, and rejects a caller temp-table
collision rather than consuming saved cases. Do not run basic checks against global vectors.
Provision the four standard POWER vectors globally with idempotent INSERTs, preserving
custom rows and duplicate user registrations. Verify against four separate session fixtures.

Before claiming support, run the setter/readback, direct OPENJSON INSERT and
snapshot transport on SQL Server and Fabric. Cover unset/session/global selection,
switching without data loss, invalid setters preserving old state, reset preserving
scope, two independent connections, and a callback changing scope after snapshots.
Check missing-table warnings/continuation and parameterized result-grid counts
without depending on a final live metadata join.
Then run the quick start, duplicates, two-phase ordering, conversion/assertion
errors, failure limits, long Unicode calls and the existing static scenario suite.
No live-database verification is implied by these implementation fragments.

## Sources

- Current invocation, results and callback lifecycle:
  `Source (SSDT project)\test\Stored Procedures\run.sql`.
- Current discovery of every procedure in `tests`:
  `Source (SSDT project)\test\Views\test.sql`.
- [Current API reference](api.md).
- [NUnit combinatorial generation](https://docs.nunit.org/articles/nunit/writing-tests/attributes/combinatorial.html).
- [Microsoft Learn: Fabric Warehouse temporary tables](https://learn.microsoft.com/en-us/fabric/data-warehouse/temp-tables).
- [Microsoft Learn: SQL Server temporary table scope](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql?view=sql-server-ver17#temporary-tables).
- [Microsoft Learn: Fabric Warehouse persisted data types](https://learn.microsoft.com/en-us/fabric/data-warehouse/data-types).
- [Microsoft Learn: Fabric Warehouse T-SQL surface area and system/data query restrictions](https://learn.microsoft.com/en-us/fabric/data-warehouse/tsql-surface-area).
- [Microsoft Learn: parameter metadata names and visibility](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-parameters-transact-sql?view=fabric).
- [Microsoft Learn: setting mutable session context](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-set-session-context-transact-sql?view=fabric).
- [Microsoft Learn: reading session context and connection behavior](https://learn.microsoft.com/en-us/sql/t-sql/functions/session-context-transact-sql?view=fabric).
- [Microsoft Learn: OPENJSON default schema, type codes and array indexes](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql?view=sql-server-ver17).
- [Microsoft Learn: ISJSON validation and array type constraint](https://learn.microsoft.com/en-us/sql/t-sql/functions/isjson-transact-sql?view=sql-server-ver17).
