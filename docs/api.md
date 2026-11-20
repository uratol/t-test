# API reference

The API installed by `install.sql`: nine scalar functions, seventeen stored procedures
and two discovery views. See [README](../README.md) for installation and platform notes.

Call scalar functions with `SET` or `SELECT`, procedures with `EXEC`, and the views
with `SELECT ... FROM`. Function signatures below show types and defaults; example
blocks are separate batches to run after installation.

For complete AAA examples and registration/cleanup recipes, see
[static tests](static-test-recipes.md), [data tests](data-test-recipes.md), and
[dimension tests](dimension-test-recipes.md).

On SQL Server, installation, registration, reset and test runs require `ROWCOUNT 0`.
If changed, issue `SET ROWCOUNT 0` directly in the calling batch beforehand.
Do not issue `SET ROWCOUNT` on Fabric Warehouse; it is unsupported.

All `assert_*` helpers are stored procedures: success returns without a result grid;
failure raises error 70001 with a `Unit-test fail:` marker. Value assertions delegate
to `is_*` functions returning bit 1/0. Legacy `fail` helpers still raise conversion
error 245. When upgrading, migrate custom scalar assertion calls to `EXEC`; the
installer replaces the old assertion functions and refreshes shipped tests.

## Table of contents

**[Assertions](#assertions)**

| API | Type | Purpose |
| --- | --- | --- |
| [test.assert_equals](#testassert_equals) | Procedure | Compare scalar values or ordered JSON results. |
| [test.assert_float_equals](#testassert_float_equals) | Procedure | Compare FLOAT values with an absolute tolerance. |
| [test.assert_null](#testassert_null) | Procedure | Require SQL NULL. |
| [test.assert_not_null](#testassert_not_null) | Procedure | Require a non-NULL value. |
| [test.assert_error](#testassert_error) | Procedure | Check caught error number, message pattern and state. |
| [test.assert_resultset_equals](#testassert_resultset_equals) | Procedure | Execute and compare two SELECT results. |
| [test.assert_query_schemas_equal](#testassert_query_schemas_equal) | Procedure | Two queries: compare their output column names, order and types. |
| [test.assert_schema_signature](#testassert_schema_signature) | Procedure | Signature + query: compare an explicit signature with the query's output schema. |

**[Comparison predicates](#comparison-predicates)**

| API | Type | Purpose |
| --- | --- | --- |
| [test.is_equal](#testis_equal) | Function | Return whether two values compare equal. |
| [test.is_equals](#testis_equals) | Function | Compatibility alias for is_equal; prefer is_equal in new code. |
| [test.is_float_equal](#testis_float_equal) | Function | Return whether FLOAT values are within an absolute tolerance. |
| [test.is_null](#testis_null) | Function | Return whether a value is NULL. |
| [test.is_not_null](#testis_not_null) | Function | Return whether a value is not NULL. |
| [test.is_json_equal](#testis_json_equal) | Function | Return whether shallow, ordered JSON values match. |

**[Other APIs](#other-apis)**

| API | Type | Purpose |
| --- | --- | --- |
| [test.format_message](#testformat_message) | Function | Replace up to four message placeholders. |
| [test.get_query_schema](#testget_query_schema) | Procedure | Return a SELECT's canonical column/type signature. |
| [test.fail](#testfail) | Function | Raise an assertion failure. |
| [test.fail_no_error](#testfail_no_error) | Procedure | Fail when an expected exception did not occur. |
| [test.throw_error](#testthrow_error) | Function | Raise a low-level error from a scalar function. |
| [test.run](#testrun) | Procedure | Discover, filter and execute tests. |
| [test.set_registration_scope](#testset_registration_scope) | Procedure | Select global or session registration storage on this connection. |
| [test.vector](#testvector) | Procedure | Append one SQL argument list for a discovered test. |
| [test.dimension](#testdimension) | Procedure | Register a JSON array of values for one test parameter. |
| [test.clear_registrations](#testclear_registrations) | Procedure | Delete vectors and dimensions from the selected store. |
| [test.log](#testlog) | Procedure | Write a formatted log message. |
| [test.throw](#testthrow) | Procedure | Raise error 70000 with optional procedure context. |
| [test.test](#testtest) | View | List test procedures and parsed naming metadata. |
| [test.test_procedures](#testtest_procedures) | View | Discover procedures across all containers. |

## Assertions

These enforce test expectations: a mismatch raises an error and fails the test.
For renamed APIs and named arguments, see the [migration table](../CHANGES.md#api-naming-cleanup).

### test.assert_equals

Compares values through `test.is_equal`: SQL text/NULL equality, a limited numeric
shortcut, then shallow JSON comparison. Two NULLs match. Text comparison follows
SQL collation and padding rules; this is not byte-exact or tolerance-based equality.

**Syntax**

```sql
EXEC test.assert_equals
    @message = ...,  -- nvarchar(max)
    @expected = ..., -- nvarchar(max)
    @actual = ...;   -- nvarchar(max)
```

**Example**

```sql
EXEC test.assert_equals N'Equal text', N'value', N'value';
DECLARE @actual int = 6 * 7;
EXEC test.assert_equals N'Equal integers', 42, @actual;
EXEC test.assert_equals N'Equal NULLs', NULL, NULL;
```

For FLOAT inputs, implicit text conversion can lose precision. Prefer
`test.assert_float_equals`, with zero tolerance when exact equality is required.
For decimal values, the numeric-string shortcut accepts only lossless conversions;
see [is_equal limits](#testis_equal) before choosing this assertion.

### test.assert_float_equals

Delegates to `test.is_float_equal`, requiring an absolute difference no greater than `@tolerance`, including the boundary.
Tolerance must be non-NULL and non-negative; zero requires exact equality. Two NULLs
match, but one NULL fails.

**Syntax**

```sql
EXEC test.assert_float_equals
    @message = ...,   -- nvarchar(max)
    @expected = ...,  -- float
    @actual = ...,    -- float
    @tolerance = ...; -- float
```

**Example**

```sql
EXEC test.assert_float_equals N'Within tolerance', 1, 1.0625, 0.125;
EXEC test.assert_float_equals N'Exact FLOAT equality', 1.25, 1.25, 0;
```

### test.assert_null

Requires `test.is_null(@value) = 1`. Empty strings, empty binary values,
zero and JSON `[]` are not NULL. Convert non-binary inputs explicitly when needed.
A scalar subquery returning no rows evaluates to NULL.

**Syntax**

```sql
EXEC test.assert_null
    @message = ..., -- nvarchar(max)
    @value = ...;   -- varbinary(max)
```

**Example**

```sql
DECLARE @value nvarchar(128), @bytes varbinary(max);
SET @value = (SELECT name FROM sys.tables WHERE 1 = 0);
SET @bytes = CONVERT(varbinary(max), @value);
EXEC test.assert_null N'Empty scalar query returns NULL', @bytes;
```

### test.assert_not_null

Requires `test.is_not_null(@value) = 1`. Empty binary values are valid.
Convert other input types explicitly with `CONVERT(varbinary(max), @value)` when needed.

**Syntax**

```sql
EXEC test.assert_not_null
    @message = ..., -- nvarchar(max)
    @value = ...;   -- varbinary(max)
```

**Example**

```sql
EXEC test.assert_not_null N'Non-NULL bytes', 0x01;
EXEC test.assert_not_null N'Empty bytes are not NULL', 0x;
```

### test.assert_error

Checks `ERROR_NUMBER()`, `ERROR_MESSAGE()` and `ERROR_STATE()` inside CATCH.
NULL or DEFAULT skips an individual filter, but a genuine caught error is still
required. The message filter uses SQL LIKE, not literal equality.
Calls outside CATCH and the `fail_no_error` sentinel are rejected.

**Syntax**

```sql
EXEC test.assert_error
    @message = ...,                   -- nvarchar(max)
    @expected_number = NULL,           -- int
    @expected_message_pattern = NULL,  -- nvarchar(max)
    @expected_state = NULL;            -- int
```

**Example**

```sql
BEGIN TRY
    THROW 51024, N'Invalid customer: 42', 17;
END TRY
BEGIN CATCH
    EXEC test.assert_error N'Customer validation', 51024, N'%Invalid customer%', 17;
    EXEC test.assert_error N'Number-only check', @expected_number = 51024;
    EXEC test.assert_error N'Message-only check', @expected_message_pattern = N'%customer%';
END CATCH;
```

Optional filters can be omitted or supplied by name. Use `[%]`, `[_]` and `[[]`
to match literal LIKE wildcard characters. There is no `is_error` predicate.

### test.assert_resultset_equals

Executes two trusted SELECT strings separately, appends
`FOR JSON PATH, INCLUDE_NULL_VALUES`, then compares the results with
`test.assert_equals`. It compares returned data, not SQL text, and emits no result
grid on success. Native query errors propagate.

Use matching output column names and explicit ORDER BY clauses when order matters.
Inputs must be non-empty, single SELECT statements without CTEs, top-level set
operators or existing FOR JSON clauses; one trailing semicolon is accepted.
Wrap UNION/EXCEPT/INTERSECT in a derived table. Dynamic SQL cannot access
caller local variables. This is not a read-only SQL validator.

The scalar `FOR JSON` capture is SQL Server behavior, not a validated Fabric
Warehouse path: Warehouse documentation disallows `FOR JSON` in subqueries.
Use schema assertions for metadata-only checks; they do not have this restriction.

**Syntax**

```sql
EXEC test.assert_resultset_equals
    @message = ...,        -- nvarchar(max)
    @expected_query = ..., -- nvarchar(max)
    @actual_query = ...;   -- nvarchar(max)
```

**Example**

```sql
EXEC test.assert_resultset_equals
    @message = N'Table names must match',
    @expected_query = N'
        SELECT object_id, name FROM sys.objects
        WHERE type = N''U'' ORDER BY object_id',
    @actual_query = N'
        SELECT object_id, name FROM sys.tables ORDER BY object_id';
```

### test.assert_query_schemas_equal

Compares column order, case-sensitive names and base SQL types, including lengths,
precision and scale. Returned values, row counts, nullability and collations are
not compared. Even empty results have a schema.

The shared metadata reader `test.get_query_schema` creates a uniquely named view in
`test`, reads its catalog metadata and drops it before comparison. SELECT rows
are not executed. No scalar `FOR JSON`, `INSERT EXEC` or result table is needed.
The caller needs `CREATE VIEW`, permission to alter the `test` schema, and access
to the referenced objects.

Supply trusted, single, view-compatible SELECT queries with unique named output
columns. CTEs and UNION are supported; leading/trailing semicolons and surrounding
whitespace are accepted. ORDER BY needs TOP or OFFSET, as in a view. Caller-local
variables, temporary tables and multiple-statement batches are not supported.
Native query/permission errors propagate; a schema mismatch raises error 70001.

```sql
EXEC test.assert_query_schemas_equal
    @message = N'Projection schema',
    @expected_query = N'SELECT CAST(1 AS int) AS id, CAST(NULL AS varchar(20)) AS name',
    @actual_query = N'SELECT CAST(99 AS int) AS id, CAST(''alpha'' AS varchar(20)) AS name';
```

### test.assert_schema_signature

Uses the same metadata reader and restrictions as `assert_query_schemas_equal`, but
accepts a canonical schema signature instead of an expected query. Format it as
`[column] type, [column] type`, using base SQL type names and no spaces inside
length/precision/scale parentheses. Column names and the signature are compared
exactly; `sysname` and alias types are described by their underlying SQL types.

```sql
EXEC test.assert_schema_signature
    @message = N'Expected projection',
    @expected_schema_signature = N'[id] int, [name] varchar(20), [amount] decimal(18,2)',
    @actual_query = N'SELECT CAST(1 AS int) AS id, CAST(NULL AS varchar(20)) AS name,
                            CAST(10.50 AS decimal(18,2)) AS amount';
```

NULL, empty and whitespace-only queries/signatures fail assertions. Nonempty
signatures are not trimmed or normalized; canonical spacing remains significant.
Schema-probe views
are cleaned on success and when query processing raises an error. These helpers
are schema assertions, not substitutes for result-data assertions.

## Comparison predicates

These return bit 1 or 0 without asserting. Use an assertion when a mismatch should
fail the test.

### test.is_equal

Returns bit 1 for equality or 0 for inequality without asserting. It first checks
SQL text/NULL equality, then tries `decimal(30,20)` equality for numeric strings
whose combined length is below 100. Otherwise, valid JSON is compared through
`test.is_json_equal`. Identical non-JSON strings can still compare equal.

The numeric shortcut is not arbitrary-precision equality. It permits only 10 integer
digits and rejects values with nonzero fractional digits beyond position 20 rather than
rounding them into false equality. Such values use text/JSON comparison instead; even
equivalent high-precision spellings can therefore compare unequal. This also applies to
`is_equals` and `assert_equals`. JSON numbers use the separate raw-value path below.

For exact decimal comparisons, choose a SQL decimal type covering your domain,
compare the typed values with `IS NOT DISTINCT FROM`, and assert the resulting bit.
Values beyond SQL's maximum decimal precision need a separate exact comparator;
FLOAT tolerance does not solve arbitrary-precision decimal equality.

**Syntax**

```sql
test.is_equal(
    @expected nvarchar(max),
    @actual nvarchar(max)
) RETURNS bit
```

**Example**

```sql
SELECT
    test.is_equal(N'001.50', N'1.5') AS numeric_equal, -- 1
    test.is_equal(NULL, NULL) AS null_equal,          -- 1
    test.is_equal(N'left', N'right') AS different;    -- 0
```

### test.is_equals

```sql
test.is_equals(@expected nvarchar(max), @actual nvarchar(max)) RETURNS bit
```

Compatibility alias for `test.is_equal`, preserving its NULL, numeric and JSON comparison
semantics. Prefer `test.is_equal` in new code; `test.assert_equals` calls it directly.

```sql
SELECT test.is_equals(NULL, NULL);       -- 1
SELECT test.is_equals(N'left', N'right'); -- 0
```

### test.is_float_equal

```sql
test.is_float_equal(@expected float, @actual float, @tolerance float) RETURNS bit
```

Returns 1 within the inclusive absolute tolerance, otherwise 0. Both NULL values
match only when tolerance is valid; one NULL does not match. Negative or NULL
tolerance returns 0, not an assertion error. Opposite-sign comparisons avoid
overflow when subtracting extreme FLOAT values.

### test.is_null

```sql
test.is_null(@value varbinary(max)) RETURNS bit
```

Returns 1 for SQL NULL, otherwise 0. Empty binary/text values are not NULL.

### test.is_not_null

```sql
test.is_not_null(@value varbinary(max)) RETURNS bit
```

Returns 1 for a non-NULL value, otherwise 0.

### test.is_json_equal

Returns bit 1 when shallow JSON objects or ordered arrays match, otherwise 0.
Property order is ignored; row order, property names, JSON types and values matter.
Numeric spellings such as `1` and `1.0` differ. Nested JSON is compared as raw text,
not recursively normalized; string values follow SQL comparison rules.

Both inputs must be valid JSON objects or both must be arrays. Invalid JSON, NULL
or an object/array mismatch returns 0. Intended result rows have unique column names
of at most 128 characters.

**Syntax**

```sql
test.is_json_equal(
    @expected nvarchar(max),
    @actual nvarchar(max)
) RETURNS bit
```

**Example**

```sql
SELECT
    test.is_json_equal(
        N'[{"id":1,"name":"A"}]', N'[{"name":"A","id":1}]') AS column_order, -- 1
    test.is_json_equal(N'[1,2]', N'[2,1]') AS row_order,                    -- 0
    test.is_json_equal(N'[1]', N'[1.0]') AS numeric_spelling;               -- 0
```

## Other APIs

Formatting, explicit failures, error helpers, execution, logging and discovery.

### test.get_query_schema

Returns a textual result-schema signature through `@schema_signature OUTPUT`; this is
not a database schema name. It uses the same metadata-only probing and permissions as
[`test.assert_query_schemas_equal`](#testassert_query_schemas_equal), without comparing results.

```sql
DECLARE @signature nvarchar(max);
EXEC test.get_query_schema
    @message = N'Read projection metadata', -- nvarchar(max)
    @query = N'SELECT 1 AS id',             -- nvarchar(max)
    @schema_signature = @signature OUTPUT; -- nvarchar(max), required OUTPUT
SELECT @signature; -- [id] int
```

### test.format_message

Replaces `%1` through `%4` sequentially and returns the formatted text. A NULL
parameter becomes `<null>`; DEFAULT leaves its placeholder unchanged. A NULL
message returns NULL. Each replacement is converted to at most 4,000 characters.
Convert dates and binary values to the desired text format explicitly.

**Syntax**

```sql
test.format_message(
    @message nvarchar(max),
    @p1 sql_variant = N'[unassigned]',
    @p2 sql_variant = N'[unassigned]',
    @p3 sql_variant = N'[unassigned]',
    @p4 sql_variant = N'[unassigned]'
) RETURNS nvarchar(max)
```

**Example**

```sql
SELECT test.format_message(
    N'Customer %1: %2', 42, N'active', DEFAULT, DEFAULT);
-- Customer 42: active
```

### test.fail

Always raises an assertion failure with the `Unit-test fail:` marker. Its declared
return type is int, but it does not return successfully. The runner classifies
this as an assertion failure rather than an unexpected exception.

**Syntax**

```sql
test.fail(@message nvarchar(max)) RETURNS int
```

**Example: intentionally fails**

```sql
SELECT test.fail(N'Expected a positive balance');
```

### test.fail_no_error

Always raises native error 70001 containing `Unit-test fail: <<No error>>`. Place it immediately after an
operation expected to throw, in the same TRY block. If the operation succeeds,
the sentinel prevents a false pass: error assertion helpers reject its marker.
This procedure never succeeds and has no scalar return value.

**Syntax**

```sql
EXEC test.fail_no_error;
```

**Example**

```sql
BEGIN TRY
    EXEC test.assert_equals N'Different values', N'left', N'right';
    EXEC test.fail_no_error;
END TRY
BEGIN CATCH
    EXEC test.assert_error N'Unequal values must fail', 70001,
        N'%Unit-test fail: Different values%', DEFAULT;
END CATCH;
```

### test.throw_error

Raises a low-level conversion error for a non-NULL message; NULL returns NULL.
Diagnostics are limited to the first 4,000 characters. Numeric or empty messages
are prefixed so they still cause an error. This helper does not add the assertion
marker; use `test.fail` to report an assertion failure.

**Syntax**

```sql
test.throw_error(@error_message nvarchar(max)) RETURNS nvarchar(max)
```

**Example: intentionally raises an error**

```sql
SELECT test.throw_error(N'Unexpected input');
```

### test.run

Runs discovered tests, prints progress, and returns per-test results and durations
grouped by tested-object schema. Assertion failures and unexpected exceptions are
reported separately; a failing run ultimately raises error 70000.

Run outside an explicit transaction. The runner does not automatically wrap each
test in a transaction; failed tests and callbacks roll back open transactions.
On SQL Server, implicit transactions must also be OFF; the runner rejects this mode without changing it.
See README for inherited session settings and Fabric-specific execution notes.

**Syntax**

```sql
EXEC test.run
    @test_names = NULL,         -- nvarchar(max), pipe-separated exact names/LIKE patterns
    @exclude_test_names = NULL, -- nvarchar(max), pipe-separated exact names/LIKE patterns
    @test_schemas = NULL,       -- nvarchar(max), comma-separated test-procedure schemas
    @exclude_test_schemas = NULL, -- nvarchar(max), excluded test-procedure schemas
    @max_failures = NULL,       -- int, defaults internally to 1000000
    @before_each_sql = NULL,    -- nvarchar(max), SQL executed before each test
    @log_proc_name = NULL,      -- nvarchar(256), defaults to test.log
    @test_object_schemas = NULL, -- nvarchar(max), comma-separated tested-object schemas
    @exclude_test_object_schemas = NULL; -- nvarchar(max), excluded tested-object schemas
```

`@test_schemas` selects the schemas containing test procedures. With neither schemas nor
names, only `tests` runs. Explicit names/patterns can select procedures in other schemas without
an additional schema argument. Specified schemas and name patterns intersect. An empty
schema selection or unmatched include name/pattern raises an error rather than passing.
Excluded name patterns that match nothing are ignored.

`@test_object_schemas` filters the parsed tested object's main schema. Its exclusion
counterpart is `@exclude_test_object_schemas`. These two parameters are appended,
preserving the first seven parameter positions.

The former `@schemas`/`@exclude_schemas` names are now
`@test_schemas`/`@exclude_test_schemas` for container selection. For the original
tested-object filtering behavior, use the object-schema pair instead. The former
singular `@test_object_schema`/`@exclude_test_object_schema` names are now plural.
Old names are not aliases; positional order, types and defaults are unchanged by renaming.

Exact procedure names take precedence over LIKE interpretation, preserving identifiers
containing `%`, `_` or brackets. Otherwise `%`, `_`, and bracket character classes follow
SQL LIKE semantics. A quoted schema prefix is literal: `[select_star].%` selects that
schema, not `selectXstar`. `%` matches any procedure name; `*` is not a wildcard.
Pipe-separated overlapping selectors preserve duplicate detection rather than silently
deduplicating calls. Use a positive failure limit. A custom logger must accept the named
arguments used by `test.log`. Callback errors are rethrown.

Explicit schema/name selection considers every stored procedure in the matching container,
not only conventionally named tests. Use dedicated test schemas and constrained patterns;
an unrestricted `%` can also select application or framework procedures.

**Example**

```sql
EXEC test.run
    @test_names = N'[tests].[test.assert_equals]|[tests].[test.assert_float_equals]',
    @max_failures = 1;

EXEC test.run @test_schemas = N'select_star';
EXEC test.run @test_names = N'[select_star].%';
EXEC test.run @test_schemas = N'tests', @test_object_schemas = N'sys';
```

To run every default-discovered test in `tests`, use `EXEC test.run;`.

Registered vectors replace the single argumentless invocation with one call per
stored row. Dimensions add their Cartesian product as independent named-argument
calls, after all selected tests' explicit vectors. Two vectors plus domains of two
and three values give eight calls. Duplicate vectors and values remain separate calls.
An unregistered procedure
still executes once. Callbacks run before
each case. Registrations and reporting metadata are captured before the first callback.
Changing scope or registration rows in a callback affects later runs, not this run.

Vector calls log start/completion events with the full EXEC in `@data`. Detail-grid
columns stay unchanged; registered rows show the static-style name and unchanged
parameters in parentheses, for example `power@vectors (-2,3,-8)`. Exact EXEC text
remains in internal results and logger data, not in the displayed test name.
Mixed/vector summaries distinguish selected procedures, planned cases and attempted
cases. Errors stop at the existing failure limit after completion is logged.
Missing sources are skipped without consulting the other store; only a test with
neither source registered uses static execution. There is no fixed case cap.
BIGINT count overflow is rejected before callbacks. One procedure's product is
materialized at a time; large products can still exhaust memory or SQL text limits.

### test.set_registration_scope

Selects vector and dimension storage for subsequent calls on this connection. **Global is the
default:** no setter call is needed when the session-context key is unset.

```sql
EXEC test.set_registration_scope @scope = N'global';  -- shared [test].[test_vectors]
EXEC test.set_registration_scope @scope = N'session'; -- caller-created #test_vectors
```

The required `nvarchar(max)` argument accepts exactly `global` or `session`;
NULL, uppercase alternatives and padding are errors. The mutable session-context
key is `ttest:vectors:scope`. Global means permanent storage in the current database,
not `##` tables or a setting for other connections. The setter creates or clears
nothing. On pooled/reused SQL Server connections, explicitly choose the intended scope.
Fabric Warehouse (EngineEdition 11) always uses global scope and never reads session context.
`test.set_registration_scope N'global'` is a no-op there; `test.set_registration_scope N'session'` raises an error
because session scope for vectors and dimensions is unavailable.

### test.vector

Appends one complete, trusted SQL argument list. SQL handles argument binding,
defaults and conversions; the framework does not split or rewrite the text.

```sql
EXEC test.vector
    @test_name = N'[tests].[test.assert_equals@vector_example]', -- nvarchar(max), required
    @arguments_sql = N'1, 1';                                   -- nvarchar(max), required
```

Use schema-qualified names of discovered tests in the current database; database/server
qualification is rejected. Accepted names are stored in canonical quoted form.
NULL or whitespace-only argument text is rejected. SQL literal text `NULL` and
`N''` are valid arguments. Use Unicode literals inside the argument list when needed.
The text is test code, not safe input from untrusted callers.
The SQL text and resolved test name must round-trip through UTF-8; invalid Unicode is rejected.

Installation creates the global table if absent, using the same ordinary DDL on both
platforms. Existing compatible tables and their saved rows are retained:

```sql
CREATE TABLE [test].[test_vectors] (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);
```

Installation also inserts the four standard `[tests].[power@vectors]` cases if missing,
without duplicating them on reinstall. The built-in POWER procedure and its vectors
are defined and deployed by `install.sql`, the authoritative framework source.

For session storage, create `#test_vectors` with the same columns directly in the
outer calling batch, then select `session`. Do not create it inside a setup procedure.
Compatible user-defined types/storage options are allowed; extra columns need defaults
or must permit NULL. Duplicate rows must be allowed. Storage APIs never provision
or drop tables; uninstallation preserves the global table and data. Global definitions
are shared and survive connection closure.

If the table is unavailable to `OBJECT_ID`, registration prints a warning and suggested
DDL, skips the call and returns before validating inputs. There is no scope fallback
or permission-diagnosis layer; the user fixes setup. Native INSERT errors propagate.
Serialize permanent edits during snapshot copying; concurrent read-only runs are supported.

### test.dimension

Registers one independent domain for a declared parameter. All arguments are
required `nvarchar(max)` values; parameter names include `@`.

Create the dimension table yourself, using this DDL for global storage or the
name `#test_dimension_values` directly in the calling batch for session storage:

```sql
CREATE TABLE [test].[test_dimension_values] (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);

EXEC test.dimension N'[tests].[replicate@dimensions]', N'@number', N'[1,2]';
EXEC test.dimension
    @test_name = N'[tests].[replicate@dimensions]',
    @parameter_name = N'@text',
    @values_json = N'["a","bb","ccc"]';
EXEC test.run N'[tests].[replicate@dimensions]'; -- Six cases.
```

Use a nonempty JSON array of numbers, strings and null. Strings become quoted
Unicode literals, numbers keep their JSON spelling, and null becomes SQL `NULL`.
Booleans, objects and nested arrays are unsupported; use numeric 0/1 for bits.
SQL performs parameter conversion. Omitted parameters retain their SQL defaults.
Stored literals (after escaping) and generated argument lists have a shared
16 MiB UTF-8 limit for Warehouse compatibility. NUL and invalid Unicode strings
are rejected rather than silently changed. These errors use the atomic INSERT's
native NOT NULL error.
Names resolve through test discovery and parameter metadata; unknown names fail.
Resolved test names must also round-trip through UTF-8.
Repeating a domain is an error, not an append or replacement. Reset the selected
store before redefining it. Duplicate array elements are retained.

An unavailable table warns and skips registration, with suggested DDL, just like
`test.vector`. Native INSERT errors propagate without leaving a partial domain.
Installation verifies `replicate@dimensions` with global domains on both engines,
then restores saved domains and drops the dimension table only if verification created it.

The runner materializes each procedure's dimension product before executing its
cases. Keep domains small: BIGINT overflow checks are not a resource budget, and
`@max_failures` does not cap generation or the number of planned combinations.
Explicit vectors add cases to the product; they do not multiply it.

### test.clear_registrations

Deletes all vector and dimension rows in the selected store, retaining scope and tables:

```sql
EXEC test.clear_registrations;
```

Pass the optional `@test_name nvarchar(max)` to clear both sources for only one test:

```sql
EXEC test.clear_registrations @test_name = N'[tests].[WELCH_TEST@generate_series]';
```

The name must resolve to a schema-qualified discovered test in this database, as for
registration. Invalid names raise an error before deleting anything. Omitting the
argument or passing NULL retains the all-tests reset.

In global scope this deletes definitions shared by all users. Reset is maintenance,
not a prerequisite for reading saved cases. An unavailable table is silently skipped.
Native DELETE errors propagate; the two deletes are not an atomic pair.
Global reset also clears the shipped POWER cases; reinstallation restores missing defaults.

### test.log

Writes a formatted message using severity-0 RAISERROR WITH NOWAIT. Severity is a
text label, not a SQL error level; logging an `error` does not fail a test.
Optional procedure and row-count context is appended. Data that exceeds the inline
budget or contains a carriage return is printed separately in chunks. The header is
limited to 2,044 UTF-16 units including its metadata tail; data chunks contain
at most 4,000 units. Truncation/chunking does not split a surrogate pair.
Data chunks retain trailing spaces. These output contracts are checked by
`tests\regression\logger-tests.ps1`, not just by SQL smoke tests.

**Syntax**

```sql
EXEC test.log
    @message = NULL,           -- nvarchar(max)
    @data = NULL,              -- nvarchar(max)
    @severity = N'debug',      -- nvarchar(8): debug, info, warning, error
    @p1 = N'!unassigned',      -- sql_variant
    @p2 = N'!unassigned',      -- sql_variant
    @p3 = N'!unassigned',      -- sql_variant
    @p4 = N'!unassigned',      -- sql_variant
    @p1_str = N'!unassigned',  -- nvarchar(max)
    @p2_str = N'!unassigned',  -- nvarchar(max)
    @p3_str = N'!unassigned',  -- nvarchar(max)
    @p4_str = N'!unassigned',  -- nvarchar(max)
    @proc_id = NULL,          -- int
    @rowcount = NULL;         -- int
```

Use `%1` through `%4` placeholders. The corresponding `@pN_str` is used when
`@pN` is unassigned; replacements still have a 4,000-character limit. Use `@data`
for longer text.

**Example**

```sql
EXEC test.log
    @message = N'Processed %1 rows for %2',
    @p1 = 42,
    @p2 = N'customers',
    @severity = N'info',
    @rowcount = 42;
```

### test.throw

Raises error 70000 with state 1 by default. An optional procedure object ID appends
`<Procedure:> [schema].[procedure]` to the message. This is an exception, not the
assertion-failure marker produced by `test.fail`. Assertions reuse this procedure
with `@error_number = 70001` and the `Unit-test fail:` prefix.

**Syntax**

```sql
EXEC test.throw
    @message = ...,        -- nvarchar(max), required
    @proc_id = NULL,       -- int
    @error_number = 70000; -- int
```

**Example: intentionally raises an error**

```sql
EXEC test.throw @message = N'Invalid test setup';
```

### test.test

Default discovery view over every procedure in the `tests` schema. It parses names such as
`[tests].[dbo.Customer@insert]` into tested object `[dbo].[Customer]` and action
`insert`. Conceptual tests can use `object@action` without an object schema.

**Syntax**

```sql
SELECT
    test_proc_full_name,
    tested_object_full_name,
    tested_object_schema_name,
    tested_object_name,
    tested_action,
    test_proc_name,
    tested_object_main_schema_name
FROM test.test;
```

**Example**

```sql
SELECT test_proc_full_name, tested_object_full_name, tested_action
FROM test.test
ORDER BY test_proc_full_name;
```

### test.test_procedures

Schema-neutral discovery used by the runner and registration APIs. It exposes the same
parsed columns as `test.test`, plus `test_proc_schema_name` and `test_proc_id`, for all
visible stored procedures. Discovery alone does not classify an application procedure as
a test: default execution still selects only `tests`; other containers require an explicit
schema or name/pattern selection. Only select schemas that contain test procedures.
