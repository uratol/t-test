# Static test recipes

A static test has no parameters and runs once per selection. Use it for a focused
behavior, a boundary, or a query contract with fixed inputs. These recipes use
built-in functions, require no application tables, and follow Arrange / Act / Assert
(AAA).

Related pages: [data-driven tests](data-test-recipes.md),
[dimension tests](dimension-test-recipes.md), and the [API reference](api.md).

## Before you start

Run the complete `install.sql` in a dedicated SQL Server 2022+ or Fabric Warehouse
test database. Run each recipe's complete SQL block, including `GO`, to create and
execute its procedure. `GO` is a client batch separator, not a T-SQL statement.
On SQL Server use `SET ROWCOUNT 0` in the calling batch if previously changed;
do not issue it on Fabric.

Names such as `[tests].[abs@recipe_static_negative]` are conceptual `object@action`
names. They satisfy discovery/naming rules without requiring a physical object named
`abs`. They have no target-object schema. Select an individual recipe with `@test_names`,
or all procedures in its container with `@test_schemas = N'tests'`.

Put declarations and boilerplate before Arrange. Set inputs and independent expected
values in Arrange, calculate actual values in Act, and call assertion procedures with
`EXEC` in Assert. Compute expressions into variables before passing them to `EXEC`.
Assertions return normally on success and raise error 70001 on mismatch.

These tests do not write application data, so they need no transaction. Do not infer
that arbitrary tests are automatically isolated: the runner does not wrap each test.
Schema recipes additionally require `CREATE VIEW` and permission to alter schema
`test`; their assertions create and drop metadata-probe views.

## Recipe 1: an exact integer result with ABS

**Contract:** the magnitude of -7 is 7. Store the expected value independently;
calling ABS again to calculate the expectation would test the function against itself.

- `test.assert_equals` compares the expected and actual values and fails on a mismatch;
  here it checks that the integer result is 7.
- `test.run` selects this procedure by name, executes it, and reports PASS or FAIL;
  it raises an error if the selected test fails.

```sql
CREATE OR ALTER PROCEDURE [tests].[abs@recipe_static_negative]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @input int, @expected int, @actual int;

    -- Arrange
    SET @input = -7;
    SET @expected = 7;

    -- Act
    SET @actual = ABS(@input);

    -- Assert
    EXEC test.assert_equals N'ABS(-7) must be 7', @expected, @actual;
END;
GO
EXEC test.run @test_names = N'[tests].[abs@recipe_static_negative]';
```

Expected: one PASS. For high-precision decimals, `assert_equals` is not an exact
numeric comparator: its numeric-string shortcut rejects lossy conversions. Compare typed
decimals independently and assert a bit, or use a suitable separate exact comparator.

## Recipe 2: NULL and fallback behavior

**Contract:** NULLIF returns NULL for equal operands; COALESCE then returns the
fallback. Check both nullability and the actual fallback value.

The NULL assertions accept `varbinary(max)`. Explicit conversion makes the signature
visible and avoids relying on implicit conversion of arbitrary input types.

- `test.assert_null` requires SQL NULL; `test.assert_not_null` requires a present
  value. Here they check the NULLIF result and the COALESCE fallback separately.
- `test.assert_equals` checks the fallback's value, not just its presence; `test.run`
  executes the named procedure and reports the combined outcome of these checks.

```sql
CREATE OR ALTER PROCEDURE [tests].[nullif@recipe_static_fallback]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @left int, @right int, @fallback int, @expected int,
        @nullable int, @actual int, @null_bytes varbinary(max),
        @actual_bytes varbinary(max);

    -- Arrange
    SET @left = 42;
    SET @right = 42;
    SET @fallback = 7;
    SET @expected = 7;

    -- Act
    SET @nullable = NULLIF(@left, @right);
    SET @actual = COALESCE(@nullable, @fallback);
    SET @null_bytes = CONVERT(varbinary(max), @nullable);
    SET @actual_bytes = CONVERT(varbinary(max), @actual);

    -- Assert
    EXEC test.assert_null N'Equal NULLIF operands must produce NULL', @null_bytes;
    EXEC test.assert_not_null N'COALESCE fallback must be present', @actual_bytes;
    EXEC test.assert_equals N'COALESCE must return the fallback', @expected, @actual;
END;
GO
EXEC test.run @test_names = N'[tests].[nullif@recipe_static_fallback]';
```

Expected: one PASS containing three checks. A non-NULL assertion alone would not
prove that the correct fallback was returned. Empty strings and empty bytes are
non-NULL; use equality or length checks when emptiness is the behavior under test.

## Recipe 3: a FLOAT result with SQRT

**Contract:** the square root of 2.25 is 1.5. State the maximum acceptable absolute
error explicitly instead of comparing FLOAT values through text conversion.

- `test.assert_float_equals` checks that the absolute difference between expected
  and actual FLOAT values is at most the supplied tolerance, including its boundary.
- `test.run` executes this named procedure and reports the assertion outcome;
  an assertion mismatch fails the test and ultimately raises a runner error.

```sql
CREATE OR ALTER PROCEDURE [tests].[sqrt@recipe_static_root]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @input float, @expected float, @actual float, @tolerance float;

    -- Arrange
    SET @input = 2.25;
    SET @expected = 1.5;
    SET @tolerance = 1E-12;

    -- Act
    SET @actual = SQRT(@input);

    -- Assert
    EXEC test.assert_float_equals N'SQRT(2.25) must be 1.5',
        @expected, @actual, @tolerance;
END;
GO
EXEC test.run @test_names = N'[tests].[sqrt@recipe_static_root]';
```

Expected: one PASS. Tolerance is inclusive, non-NULL, and non-negative. It is an
absolute difference, not a relative percentage or number of decimal digits.

## Recipe 4: an expected conversion error

**Contract:** CAST must reject a nonnumeric string as an integer. The sentinel makes
the test fail if the operation unexpectedly succeeds. The assertion must remain
inside CATCH because that is where the error record is available.

- `test.assert_error` verifies the caught error against its supplied number, optional
  LIKE message pattern, and optional state; here only native error number 245 is checked.
- `test.fail_no_error` fails if CAST unexpectedly succeeds. Its sentinel is rejected
  by `assert_error`; `test.run` reports PASS only when the expected error is verified.

```sql
CREATE OR ALTER PROCEDURE [tests].[cast@recipe_static_invalid_int]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @input nvarchar(32), @actual int, @expected_number int;

    -- Arrange
    SET @input = N'not-an-integer';
    SET @expected_number = 245;

    -- Act
    BEGIN TRY
        SET @actual = CAST(@input AS int);
        EXEC test.fail_no_error;
    END TRY
    BEGIN CATCH
        -- Assert
        EXEC test.assert_error N'CAST must reject nonnumeric integer input',
            @expected_number = @expected_number;
    END CATCH;
END;
GO
EXEC test.run @test_names = N'[tests].[cast@recipe_static_invalid_int]';
```

Expected: one PASS, not a failed runner case. The expected SQL error was caught and
verified. Error 245 is the native integer-conversion error; avoid matching localized
message text unless the test deliberately targets it. `assert_error` also supports
optional LIKE-pattern and state filters.

If CAST stops raising an error, `fail_no_error` raises the `<<No error>>` sentinel.
`assert_error` rejects that sentinel even when filters are omitted. An empty CATCH
would incorrectly hide the regression.

## Recipe 5: ordered result data, including NULL

**Contract:** projecting ABS over three rows preserves IDs and returns magnitudes
3, 0, and NULL. The expected query contains literals, not another ABS expression.

The assertion executes both SELECTs during Assert; Act prepares the actual query
because this helper combines execution and comparison. Query text must be trusted.
It cannot reference this procedure's local variables.

This recipe requires SQL Server's scalar `FOR JSON` capture. It is not a validated
Warehouse recipe; Warehouse documentation disallows `FOR JSON` inside subqueries.
Use Recipe 6 when only the projection schema matters.

- `test.assert_resultset_equals` executes two trusted SELECT strings and compares
  their ordered JSON data, retaining NULLs; it does not compare column metadata.
- `test.run` executes the named test and reports its result; different row values,
  missing rows, or a different row order cause the assertion to fail.

```sql
CREATE OR ALTER PROCEDURE [tests].[abs@recipe_static_rows]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

    -- Arrange
    SET @expected_query = N'
        SELECT id, magnitude
        FROM (VALUES (1, 3), (2, 0), (3, CAST(NULL AS int))) v(id, magnitude)
        ORDER BY id';

    -- Act
    SET @actual_query = N'
        SELECT id, ABS(input) AS magnitude
        FROM (VALUES (1, -3), (2, 0), (3, CAST(NULL AS int))) v(id, input)
        ORDER BY id';

    -- Assert
    EXEC test.assert_resultset_equals N'ABS projection must preserve ordered rows',
        @expected_query, @actual_query;
END;
GO
EXEC test.run @test_names = N'[tests].[abs@recipe_static_rows]';
```

Expected: one PASS. The helper appends `FOR JSON PATH, INCLUDE_NULL_VALUES`; do not
include your own JSON clause. Both queries have matching ORDER BY clauses because
row order matters. Column order does not. Use one SELECT per string, without CTEs
or additional statements. This asserts data, not column types or empty-result schema.

## Recipe 6: a projection schema

**Contract:** CAST exposes columns `[id] int` and `[label] varchar(20)` in that order.
Check the same contract using an explicit signature and a reference query.

Both helpers inspect metadata without reading result rows. They compare ordered,
case-sensitive column names and base types, including length, precision, and scale.
Neither compares nullability or collation. `test.run` executes the named procedure
and reports the combined outcome of its two assertions.

- `test.assert_schema_signature` compares one SELECT's schema with an explicit signature,
  here `[id] int, [label] varchar(20)`; use it for a fixed, written column contract.
- `test.assert_query_schemas_equal` compares the schemas of two SELECTs, using the expected
  query as the reference; their returned row values may differ without failing.

```sql
CREATE OR ALTER PROCEDURE [tests].[cast@recipe_static_schema]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected_schema_signature nvarchar(max), @expected_query nvarchar(max),
        @actual_query nvarchar(max);

    -- Arrange
    SET @expected_schema_signature = N'[id] int, [label] varchar(20)';
    SET @expected_query =
        N'SELECT CAST(0 AS int) AS id, CAST(NULL AS varchar(20)) AS label';

    -- Act
    SET @actual_query =
        N'SELECT CAST(7 AS int) AS id, CAST(''seven'' AS varchar(20)) AS label';

    -- Assert
    EXEC test.assert_schema_signature N'CAST projection must match the declared contract',
        @expected_schema_signature, @actual_query;
    EXEC test.assert_query_schemas_equal N'CAST projection must match the reference schema',
        @expected_query, @actual_query;
END;
GO
EXEC test.run @test_names = N'[tests].[cast@recipe_static_schema]';
```

Expected: one PASS containing two checks.

Queries must be view-compatible with unique named columns. No local variables or
temporary tables; ORDER BY needs TOP or OFFSET. A schema assertion is not a data
assertion, so combine it with recipe 5 when both contracts matter.

## Assertion coverage and cleanup

These are usage recipes, not a substitute for the framework's own regression suite.
Together they demonstrate all eight assertion procedures:

| Assertion | Recipe |
|---|---|
| `assert_equals` | 1 and 2 |
| `assert_null`, `assert_not_null` | 2 |
| `assert_float_equals` | 3 |
| `assert_error` and the `fail_no_error` helper | 4 |
| `assert_resultset_equals` | 5 |
| `assert_schema_signature`, `assert_query_schemas_equal` | 6 |

Procedures remain installed and are included in an unfiltered `test.run`. They have
no registrations. To remove just these recipes:

- `DROP PROCEDURE IF EXISTS` removes only the six named recipe procedures, so
  `test.run` no longer discovers them; unrelated tests and framework helpers remain.
- `test.clear_registrations` is unnecessary here because static recipes register no vectors or
  dimensions; no shared registration tables or application data are deleted.

```sql
DROP PROCEDURE IF EXISTS [tests].[abs@recipe_static_negative];
DROP PROCEDURE IF EXISTS [tests].[nullif@recipe_static_fallback];
DROP PROCEDURE IF EXISTS [tests].[sqrt@recipe_static_root];
DROP PROCEDURE IF EXISTS [tests].[cast@recipe_static_invalid_int];
DROP PROCEDURE IF EXISTS [tests].[abs@recipe_static_rows];
DROP PROCEDURE IF EXISTS [tests].[cast@recipe_static_schema];
```
