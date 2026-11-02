# API reference

The API installed by `install.sql`: eleven scalar functions, four stored procedures
and one discovery view. See [README](README.md) for installation and platform notes.

Call scalar functions with `SET` or `SELECT`, procedures with `EXEC`, and the view
with `SELECT ... FROM`. Function signatures below show types and defaults; example
blocks are separate batches to run after installation.

Value assertions return `N''` on success; error assertions return `int NULL`.
Assertion failures raise conversion error 245 with a `Unit-test fail:` marker.
Assign successful assertion results to variables to avoid empty result grids.

## Table of contents

| API | Type | Purpose |
| --- | --- | --- |
| [test.assert_equals](#testassert_equals) | Function | Compare scalar values or ordered JSON results. |
| [test.assert_float_equals](#testassert_float_equals) | Function | Compare FLOAT values with an absolute tolerance. |
| [test.assert_null](#testassert_null) | Function | Require SQL NULL. |
| [test.assert_not_null](#testassert_not_null) | Function | Require a non-NULL value. |
| [test.assert_error](#testassert_error) | Function | Check caught error number, message pattern and state. |
| [test.is_equal](#testis_equal) | Function | Return whether two values compare equal. |
| [test.is_json_equal](#testis_json_equal) | Function | Return whether shallow, ordered JSON values match. |
| [test.format_message](#testformat_message) | Function | Replace up to four message placeholders. |
| [test.fail](#testfail) | Function | Raise an assertion failure. |
| [test.fail_no_error](#testfail_no_error) | Function | Fail when an expected exception did not occur. |
| [test.throw_error](#testthrow_error) | Function | Raise a low-level error from a scalar function. |
| [test.assert_resultset_equals](#testassert_resultset_equals) | Procedure | Execute and compare two SELECT results. |
| [test.run](#testrun) | Procedure | Discover, filter and execute tests. |
| [test.log](#testlog) | Procedure | Write a formatted log message. |
| [test.throw](#testthrow) | Procedure | Raise error 70000 with optional procedure context. |
| [test.test](#testtest) | View | List test procedures and parsed naming metadata. |

## test.assert_equals

Compares values through `test.is_equal`: SQL text/NULL equality, a limited numeric
shortcut, then shallow JSON comparison. Two NULLs match. Text comparison follows
SQL collation and padding rules; this is not byte-exact or tolerance-based equality.

**Syntax**

```sql
test.assert_equals(
    @message nvarchar(max),
    @expected nvarchar(max),
    @actual nvarchar(max)
) RETURNS nvarchar(max)
```

**Example**

```sql
DECLARE @result nvarchar(max);
SET @result = test.assert_equals(N'Equal text', N'value', N'value');
SET @result = test.assert_equals(N'Equal integers', 42, 6 * 7);
SET @result = test.assert_equals(N'Equal NULLs', NULL, NULL);
```

For FLOAT inputs, implicit text conversion can lose precision. Prefer
`test.assert_float_equals`, with zero tolerance when exact equality is required.

## test.assert_float_equals

Requires an absolute difference no greater than `@tolerance`, including the boundary.
Tolerance must be non-NULL and non-negative; zero requires exact equality. Two NULLs
match, but one NULL fails. Returns `N''` on success.

**Syntax**

```sql
test.assert_float_equals(
    @message nvarchar(max),
    @expected float,
    @actual float,
    @tolerance float
) RETURNS nvarchar(max)
```

**Example**

```sql
DECLARE @result nvarchar(max);
SET @result = test.assert_float_equals(N'Within tolerance', 1, 1.0625, 0.125);
SET @result = test.assert_float_equals(N'Exact FLOAT equality', 1.25, 1.25, 0);
```

## test.assert_null

Requires SQL NULL and returns `N''` on success. Empty strings, empty binary values,
zero and JSON `[]` are not NULL. Convert non-binary inputs explicitly when needed.
A scalar subquery returning no rows evaluates to NULL.

**Syntax**

```sql
test.assert_null(
    @message nvarchar(max),
    @value varbinary(max)
) RETURNS nvarchar(max)
```

**Example**

```sql
DECLARE @value nvarchar(128), @result nvarchar(max);
SET @value = (SELECT name FROM sys.tables WHERE 1 = 0);
SET @result = test.assert_null(
    N'Empty scalar query returns NULL', CONVERT(varbinary(max), @value));
```

## test.assert_not_null

Requires a non-NULL value and returns `N''` on success. Empty binary values are valid.
Convert other input types explicitly with `CONVERT(varbinary(max), @value)` when needed.

**Syntax**

```sql
test.assert_not_null(
    @message nvarchar(max),
    @value varbinary(max)
) RETURNS nvarchar(max)
```

**Example**

```sql
DECLARE @result nvarchar(max);
SET @result = test.assert_not_null(N'Non-NULL bytes', 0x01);
SET @result = test.assert_not_null(N'Empty bytes are not NULL', 0x);
```

## test.assert_error

Checks `ERROR_NUMBER()`, `ERROR_MESSAGE()` and `ERROR_STATE()` inside CATCH.
NULL or DEFAULT skips an individual filter, but a genuine caught error is still
required. The message filter uses SQL LIKE, not literal equality. Returns `int NULL`
on success; calls outside CATCH and the `fail_no_error()` sentinel are rejected.

**Syntax**

```sql
test.assert_error(
    @message nvarchar(max),
    @expected_number int = NULL,
    @expected_message_pattern nvarchar(max) = NULL,
    @expected_state int = NULL
) RETURNS int
```

**Example**

```sql
DECLARE @result int;
BEGIN TRY
    THROW 51024, N'Invalid customer: 42', 17;
END TRY
BEGIN CATCH
    SET @result = test.assert_error(
        N'Customer validation', 51024, N'%Invalid customer%', 17);
    SET @result = test.assert_error(
        N'Number-only check', 51024, DEFAULT, DEFAULT);
    SET @result = test.assert_error(
        N'Message-only check', DEFAULT, N'%customer%', DEFAULT);
END CATCH;
```

Scalar-function calls supply every argument position; use DEFAULT for omitted
filters. Use `[%]`, `[_]` and `[[]` to match literal LIKE wildcard characters.

## test.is_equal

Returns bit 1 for equality or 0 for inequality without asserting. It first checks
SQL text/NULL equality, then tries `decimal(30,20)` equality for numeric strings
whose combined length is below 100. Otherwise, valid JSON is compared through
`test.is_json_equal`. Identical non-JSON strings can still compare equal.

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

## test.is_json_equal

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

## test.format_message

Replaces `%1` through `%4` sequentially and returns the formatted text. A NULL
parameter becomes `<null>`; DEFAULT leaves its placeholder unchanged. A NULL
message returns NULL. Each replacement is converted to at most 4,000 characters.
Convert dates and binary values to the desired text format explicitly.

**Syntax**

```sql
test.format_message(
    @msg nvarchar(max),
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

## test.fail

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

## test.fail_no_error

Always raises error 245 containing `<<No error>>`. Place it immediately after an
operation expected to throw, in the same TRY block. If the operation succeeds,
the sentinel prevents a false pass: error assertion helpers reject its marker.
The declared return type is `nvarchar(max)`, but the function never succeeds.

**Syntax**

```sql
test.fail_no_error() RETURNS nvarchar(max)
```

**Example**

```sql
DECLARE @result nvarchar(max), @error_result int;
BEGIN TRY
    SET @result = test.assert_equals(N'Different values', N'left', N'right');
    SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
    SET @error_result = test.assert_error(
        N'Unequal values must fail', 245,
        N'%Unit-test fail: Different values%', DEFAULT);
END CATCH;
```

## test.throw_error

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

## test.assert_resultset_equals

Executes two trusted SELECT strings separately, appends
`FOR JSON PATH, INCLUDE_NULL_VALUES`, then compares the results with
`test.assert_equals`. It compares returned data, not SQL text, and emits no result
grid on success. Native query errors propagate.

Use matching output column names and explicit ORDER BY clauses when order matters.
Inputs must be non-empty, single SELECT statements without CTEs or existing
FOR JSON clauses; one trailing semicolon is accepted. Dynamic SQL cannot access
caller local variables. This is not a read-only SQL validator.

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

## test.run

Runs discovered tests, prints progress, and returns per-test results and durations
grouped by tested-object schema. Assertion failures and unexpected exceptions are
reported separately; a failing run ultimately raises error 70000.

Run outside an explicit transaction. The runner does not automatically wrap each
test in a transaction; failed tests and callbacks roll back open transactions.
See README for inherited session settings and Fabric-specific execution notes.

**Syntax**

```sql
EXEC test.run
    @test_names = NULL,         -- nvarchar(max), pipe-separated test names
    @exclude_test_names = NULL, -- nvarchar(max), pipe-separated test names
    @schemas = NULL,            -- nvarchar(256), comma-separated object schemas
    @exclude_schemas = NULL,    -- nvarchar(256), comma-separated object schemas
    @limit_failed = NULL,       -- int, defaults internally to 1000000
    @before_callback = NULL,    -- nvarchar(max), SQL executed before each test
    @log_proc_name = NULL;      -- nvarchar(256), defaults to test.log
```

Schema filters use the tested object's main schema, not the `tests` registration
schema. Use fully qualified test names and a positive failure limit. A custom logger
must accept the named arguments used by `test.log`. Callback errors are rethrown.

**Example**

```sql
EXEC test.run
    @test_names = N'[tests].[test.assert_equals]|[tests].[test.assert_float_equals]',
    @limit_failed = 1;
```

To run every discovered test, use `EXEC test.run;`.

## test.log

Writes a formatted message using severity-0 RAISERROR WITH NOWAIT. Severity is a
text label, not a SQL error level; logging an `error` does not fail a test.
Optional procedure and row-count context is appended. Long or multiline `@data`
is printed separately in chunks.

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

## test.throw

Raises error 70000 with state 1. An optional procedure object ID appends
`<Procedure:> [schema].[procedure]` to the message. This is an exception, not the
assertion-failure marker produced by `test.fail`.

**Syntax**

```sql
EXEC test.throw
    @message = ...,   -- nvarchar(max), required
    @proc_id = NULL;  -- int
```

**Example: intentionally raises an error**

```sql
EXEC test.throw @message = N'Invalid test setup';
```

## test.test

Discovery view over every procedure in the `tests` schema. It parses names such as
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
