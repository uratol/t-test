# Data-driven test recipes

A data test is a parameterized test procedure with explicit vectors registered by
`test.vector`. Each vector is one complete case, including independent expected
values. Choose vectors when inputs and expectations belong together rather than
forming independent domains.

Related pages: [static tests](static-test-recipes.md),
[dimension tests](dimension-test-recipes.md), and [vector API](api.md#testvector).

## Before you start

Install `install.sql` in a dedicated SQL Server 2022+ or Fabric Warehouse test database.
Run the setup once, then each complete recipe block including `GO`:

- `test.set_registration_scope N'global'` selects the permanent registration stores used by
  `test.vector`, `test.clear_registrations`, and `test.run`; Fabric supports only this scope.
- Scope selection does not register or clear cases. Later calls use shared saved
  definitions, so changing or resetting them requires coordination with other users.

```sql
EXEC test.set_registration_scope N'global';
```

Global vectors survive connection closure and are shared by all callers. Installation
creates `[test].[test_vectors]`; registration only warns and skips if its store is
unavailable. Do not run setup/reset concurrently with other users of these names.
On SQL Server use `SET ROWCOUNT 0` in the calling batch if previously changed;
do not issue it on Fabric.

Each recipe creates a uniquely named conceptual test and resets only that procedure
before registering cases. Do not use bare `test.clear_registrations`: it deletes all vectors and
dimensions in the selected scope, including shipped POWER vectors.

Declarations go before Arrange. Inputs arrive as parameters; Arrange records the
case's expectation and diagnostic message, Act evaluates the built-in function,
and Assert verifies the result. Never register vectors inside the test itself.

## Recipe 1: explicit ABS cases

**Contract:** negative and positive inputs have positive magnitudes, zero stays zero,
and NULL stays NULL. The expectation is supplied with each input, not calculated
with ABS. A NULL case checks both nullability and value equality.

- `test.assert_equals` checks the expected magnitude; `test.assert_null` and
  `test.assert_not_null` additionally verify the appropriate nullability for each case.
- `test.clear_registrations @test_name` clears only this test's vectors and dimensions;
  `test.vector` appends each explicit case, and `test.run` executes the saved cases.

```sql
CREATE OR ALTER PROCEDURE [tests].[abs@recipe_data_magnitude]
    @input int,
    @expected int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actual int, @actual_bytes varbinary(max), @message nvarchar(max);

    -- Arrange
    SET @message = CONCAT(N'ABS vector input=', COALESCE(CONVERT(nvarchar(12),
        @input), N'NULL'), N' must match its expected magnitude');

    -- Act
    SET @actual = ABS(@input);
    SET @actual_bytes = CONVERT(varbinary(max), @actual);

    -- Assert
    IF @expected IS NULL
        EXEC test.assert_null @message, @actual_bytes;
    ELSE
        EXEC test.assert_not_null @message, @actual_bytes;
    EXEC test.assert_equals @message, @expected, @actual;
END;
GO
EXEC test.clear_registrations @test_name = N'[tests].[abs@recipe_data_magnitude]';
EXEC test.vector N'[tests].[abs@recipe_data_magnitude]', N'-7, 7';
EXEC test.vector N'[tests].[abs@recipe_data_magnitude]', N'0, 0';
EXEC test.vector N'[tests].[abs@recipe_data_magnitude]', N'7, 7';
EXEC test.vector N'[tests].[abs@recipe_data_magnitude]', N'NULL, NULL';
EXEC test.run @test_names = N'[tests].[abs@recipe_data_magnitude]';
```

Expected: four PASS cases with arguments in their labels. The runner replaces the
procedure's single static call with the saved vectors. Duplicate registrations
execute separately; targeted reset makes repeating the registration block predictable.

## Recipe 2: FLOAT reference values with per-case tolerance

**Contract:** SQRT returns the reference root for each input within that case's
absolute tolerance. Use exact roots as references and make the tolerance visible
in the data instead of hard-coding an unexplained comparison rule.

- `test.assert_float_equals` compares the actual root with its reference using the
  case's inclusive absolute tolerance; valid tolerance is required even for NULL pairs.
- `test.clear_registrations @test_name` clears this procedure's cases, `test.vector` registers the
  supplied argument lists, and `test.run` executes one invocation per saved vector.

```sql
CREATE OR ALTER PROCEDURE [tests].[sqrt@recipe_data_roots]
    @input float,
    @expected float,
    @tolerance float
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actual float, @message nvarchar(max);

    -- Arrange
    SET @message = CONCAT(N'SQRT vector input=',
        COALESCE(CONVERT(nvarchar(32), @input, 3), N'NULL'),
        N' must match its reference root');

    -- Act
    SET @actual = SQRT(@input);

    -- Assert
    EXEC test.assert_float_equals @message, @expected, @actual, @tolerance;
END;
GO
EXEC test.clear_registrations @test_name = N'[tests].[sqrt@recipe_data_roots]';
EXEC test.vector N'[tests].[sqrt@recipe_data_roots]', N'0, 0, 0';
EXEC test.vector N'[tests].[sqrt@recipe_data_roots]', N'4, 2, 1E-12';
EXEC test.vector N'[tests].[sqrt@recipe_data_roots]', N'2.25, 1.5, 1E-12';
EXEC test.vector N'[tests].[sqrt@recipe_data_roots]',
    N'@tolerance=1E-12, @expected=3, @input=9';
EXEC test.vector N'[tests].[sqrt@recipe_data_roots]', N'NULL, NULL, 0';
EXEC test.run @test_names = N'[tests].[sqrt@recipe_data_roots]';
```

Expected: five PASS cases. Named arguments may be reordered; they still address the
declared procedure parameters. The NULL case uses a valid zero tolerance because
NULL or negative tolerances fail even when both compared values are NULL.

Do not replace this with `assert_equals` on FLOAT values: implicit text conversion
can lose precision. Tolerance-based FLOAT comparison is also not a remedy for exact
arbitrary-precision decimal comparisons.

## Recipe 3: invalid conversion inputs

**Contract:** two different nonnumeric strings must produce integer-conversion error
245. Parameterizing both the input and expected error keeps exception cases explicit.

- `test.assert_error` checks the native error number inside CATCH; `test.fail_no_error`
  makes an unexpectedly successful conversion fail rather than silently pass.
- `test.clear_registrations @test_name` clears this procedure's registrations, `test.vector`
  supplies each invalid input and error number, and `test.run` executes both cases.

```sql
CREATE OR ALTER PROCEDURE [tests].[cast@recipe_data_errors]
    @input nvarchar(64),
    @expected_number int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @actual int, @message nvarchar(max);

    -- Arrange
    SET @message = CONCAT(N'CAST must reject integer input <', @input, N'>');

    -- Act
    BEGIN TRY
        SET @actual = CAST(@input AS int);
        EXEC test.fail_no_error;
    END TRY
    BEGIN CATCH
        -- Assert
        EXEC test.assert_error @message, @expected_number = @expected_number;
    END CATCH;
END;
GO
EXEC test.clear_registrations @test_name = N'[tests].[cast@recipe_data_errors]';
EXEC test.vector N'[tests].[cast@recipe_data_errors]', N'N''abc'', 245';
EXEC test.vector N'[tests].[cast@recipe_data_errors]', N'N''12x'', 245';
EXEC test.run @test_names = N'[tests].[cast@recipe_data_errors]';
```

Expected: two PASS cases. The outer SQL string contains an inner Unicode literal;
double quotes of the SQL apostrophe produce `N'abc'` when the vector is executed.
Do not omit the sentinel or swallow CATCH errors. A successful conversion must fail
this test, and a different native error must not count as the expected conversion.

## Running and extending cases

Run all three recipe procedures, retaining individual case reports. Procedure
arguments cannot be concatenated inline in EXEC, so calculate the selection first:

- `test.run @test_names` selects the three procedures from the pipe-separated list
  and replays their saved vectors, reporting each invocation separately.
- `test.run` does not register or reset cases; existing definitions determine the
  count, and any failed assertion or unexpected error makes the run fail.

```sql
DECLARE @names nvarchar(max);
SET @names = N'[tests].[abs@recipe_data_magnitude]|'
    + N'[tests].[sqrt@recipe_data_roots]|[tests].[cast@recipe_data_errors]';
EXEC test.run @test_names = @names;
```

Expected: eleven PASS cases if you registered only the supplied vectors and no dimensions.
To debug one case directly, pass its arguments:

- Direct `EXEC` calls the test with just these arguments; it bypasses `test.run`,
  saved vectors, runner callbacks, and the runner's result summaries.
- Inside this test, `assert_not_null` checks presence and `assert_equals` checks the
  expected magnitude; the NULL branch would use `assert_null` instead.

```sql
EXEC [tests].[abs@recipe_data_magnitude] @input = -7, @expected = 7;
```

Vector arguments are trusted SQL, not JSON or a safe user-input transport. They may
contain expressions, NULL, DEFAULT, positional arguments, or named arguments.
Never feed untrusted input into registration. The procedure receives SQL-converted
values; conversion errors before its body cannot be caught by its internal CATCH.

These recipes exercise `assert_equals`, both NULL assertions, `assert_float_equals`,
and `assert_error`. For ordered result data and query schemas, use the
[static assertion recipes](static-test-recipes.md#assertion-coverage-and-cleanup).

## Scope and cleanup

Fabric supports global scope only. On SQL Server, optional session scope requires
you to create `#test_vectors` directly in the calling batch with the
[documented columns](api.md#testvector), then select `session` on that connection.
Global cases are not copied into the session store. Do not create the temp registry
inside a setup procedure, where its lifetime would end too soon.

For global cleanup, reset before dropping each recipe procedure: reset requires
the name to resolve to a discovered test. This preserves unrelated registrations.

- `test.set_registration_scope N'global'` selects shared storage; targeted `test.clear_registrations` deletes
  only these procedures' vector and dimension rows, leaving all other tests intact.
- `DROP PROCEDURE IF EXISTS` then removes the recipe procedures from discovery.
  Reset comes first because it requires each name to resolve to an existing test.

```sql
EXEC test.set_registration_scope N'global';
EXEC test.clear_registrations @test_name = N'[tests].[abs@recipe_data_magnitude]';
EXEC test.clear_registrations @test_name = N'[tests].[sqrt@recipe_data_roots]';
EXEC test.clear_registrations @test_name = N'[tests].[cast@recipe_data_errors]';
DROP PROCEDURE IF EXISTS [tests].[abs@recipe_data_magnitude];
DROP PROCEDURE IF EXISTS [tests].[sqrt@recipe_data_roots];
DROP PROCEDURE IF EXISTS [tests].[cast@recipe_data_errors];
```
