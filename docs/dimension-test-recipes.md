# Dimension test recipes

A dimension test is a parameterized procedure whose independent parameter domains
are registered with `test.dimension`. The runner executes every combination.
Choose dimensions when every cross-combination is meaningful; use
[data vectors](data-test-recipes.md) when each input needs its own expected output.

Related pages: [static tests](static-test-recipes.md) and
[dimension API](api.md#testdimension).

## Before you start

Install `install.sql` in a dedicated SQL Server 2022+ or Fabric Warehouse database.
Run this setup once before the recipes. Global registration is shared, so coordinate
table creation and edits with other users:

- `test.set_registration_scope N'global'` selects permanent stores for `test.dimension`,
  `test.clear_registrations`, and `test.run`; Fabric Warehouse does not support session scope.
- The conditional CREATE TABLE provisions the domain store if missing; it neither
  clears existing rows nor registers cases. `test.dimension` does not create it itself.

```sql
EXEC test.set_registration_scope N'global';
IF OBJECT_ID(N'[test].[test_dimension_values]', N'U') IS NULL
BEGIN
    CREATE TABLE [test].[test_dimension_values] (
        procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
        parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
        value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
    );
END;
```

Installation only creates this dimension table temporarily for its own verification
when missing; it may not exist afterward. Registration never creates a missing store:
it warns and skips. On SQL Server use `SET ROWCOUNT 0` in the calling batch if
previously changed; do not issue it on Fabric.

Run each complete recipe block including `GO`. Test names are conceptual
`object@action` names, discoverable through `test.test`. Declarations precede Arrange;
independent expected values are prepared in Arrange, the function is evaluated in Act,
and assertions are called in Assert. These recipes do not write application data.

## Recipe 1: REPLICATE across counts and tokens

**Contract:** repeating either `a` or `bc` zero, one, or three times produces the
specified text and byte length. There are 3 x 2 = 6 combinations, including the empty
result for count zero and a multi-character token.

Prepare reference text with a small literal lookup, not another REPLICATE call.
The byte-length assertion catches trailing-space/length differences that ordinary
SQL text equality can ignore. Casting input as `nvarchar(max)` makes the intended
REPLICATE output capacity explicit.

- `test.assert_not_null` checks that the reference and result exist, including empty
  strings; `test.assert_equals` compares both the expected text and its byte length.
- Targeted `test.clear_registrations` clears this test's registrations; `test.dimension` saves each
  parameter domain, and `test.run` executes their 3 x 2 product as six separate cases.

```sql
CREATE OR ALTER PROCEDURE [tests].[replicate@recipe_dimension_tokens]
    @count int,
    @token nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected nvarchar(max), @actual nvarchar(max),
        @expected_bytes bigint, @actual_bytes bigint,
        @nonnull_bytes varbinary(max), @reference_bytes varbinary(max),
        @message nvarchar(max);

    -- Arrange
    SET @expected = CASE @token
        WHEN N'a' THEN CASE @count
            WHEN 0 THEN N'' WHEN 1 THEN N'a' WHEN 3 THEN N'aaa' END
        WHEN N'bc' THEN CASE @count
            WHEN 0 THEN N'' WHEN 1 THEN N'bc' WHEN 3 THEN N'bcbcbc' END
    END;
    SET @expected_bytes = DATALENGTH(@expected);
    SET @reference_bytes = CONVERT(varbinary(max), @expected);
    SET @message = CONCAT(N'REPLICATE count=', @count, N' token=<', @token, N'>');

    -- Act
    SET @actual = REPLICATE(@token, @count);
    SET @actual_bytes = DATALENGTH(@actual);
    SET @nonnull_bytes = CONVERT(varbinary(max), @actual);

    -- Assert
    EXEC test.assert_not_null N'Reference lookup must cover this combination',
        @reference_bytes;
    EXEC test.assert_not_null @message, @nonnull_bytes;
    EXEC test.assert_equals @message, @expected, @actual;
    EXEC test.assert_equals N'REPLICATE byte length must match the reference',
        @expected_bytes, @actual_bytes;
END;
GO
EXEC test.clear_registrations @test_name = N'[tests].[replicate@recipe_dimension_tokens]';
EXEC test.dimension N'[tests].[replicate@recipe_dimension_tokens]',
    N'@count', N'[0,1,3]';
EXEC test.dimension N'[tests].[replicate@recipe_dimension_tokens]',
    N'@token', N'["a","bc"]';
EXEC test.run @test_names = N'[tests].[replicate@recipe_dimension_tokens]';
```

Expected: six PASS cases. Empty bytes are non-NULL, so count zero legitimately
passes `assert_not_null`. The reference guard fails if someone extends the domains
without extending the lookup; an uncovered case cannot pass by comparing two NULLs.
For a large irregular lookup, explicit vectors are clearer.

## Recipe 2: NULLIF across equal, unequal, and NULL inputs

**Contract:** NULLIF returns NULL when its first input is NULL or the two inputs
are equal; otherwise it returns the first input. The independent reference lookup
covers every combination of left `[null,1,2]` and right `[1,2]`.

- `test.assert_equals` checks lookup coverage and the returned value; `assert_null`
  or `assert_not_null` checks whether that particular pair must produce SQL NULL.
- Targeted `test.clear_registrations` clears this test's registrations; `test.dimension` saves the
  two independent domains, and `test.run` executes all six cross-combinations.

```sql
CREATE OR ALTER PROCEDURE [tests].[nullif@recipe_dimension_pairs]
    @left int,
    @right int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected int, @actual int, @actual_bytes varbinary(max), @covered bit,
        @message nvarchar(max);

    -- Arrange
    SET @covered = CASE WHEN (@left IS NULL OR @left IN (1, 2))
        AND @right IN (1, 2) THEN 1 ELSE 0 END;
    SET @expected = CASE
        WHEN @left IS NULL THEN NULL
        WHEN @left = 1 AND @right = 1 THEN NULL
        WHEN @left = 1 AND @right = 2 THEN 1
        WHEN @left = 2 AND @right = 1 THEN 2
        WHEN @left = 2 AND @right = 2 THEN NULL
    END;
    SET @message = CONCAT(N'NULLIF left=',
        COALESCE(CONVERT(nvarchar(12), @left), N'NULL'), N' right=', @right);

    -- Act
    SET @actual = NULLIF(@left, @right);
    SET @actual_bytes = CONVERT(varbinary(max), @actual);

    -- Assert
    EXEC test.assert_equals N'Reference lookup must cover this pair', 1, @covered;
    IF @expected IS NULL
        EXEC test.assert_null @message, @actual_bytes;
    ELSE
        EXEC test.assert_not_null @message, @actual_bytes;
    EXEC test.assert_equals @message, @expected, @actual;
END;
GO
EXEC test.clear_registrations @test_name = N'[tests].[nullif@recipe_dimension_pairs]';
EXEC test.dimension N'[tests].[nullif@recipe_dimension_pairs]',
    N'@left', N'[null,1,2]';
EXEC test.dimension N'[tests].[nullif@recipe_dimension_pairs]',
    N'@right', N'[1,2]';
EXEC test.run @test_names = N'[tests].[nullif@recipe_dimension_pairs]';
```

Expected: six PASS cases: four NULL results and two non-NULL results. JSON `null`
becomes SQL NULL, not the string `N'NULL'`. Update the independent expectation when
extending either domain; the reference guard deliberately accepts only these inputs.

## Registration rules and predictable counts

| Rule | Meaning |
|---|---|
| Domain format | A nonempty JSON array of numbers, strings, or null |
| Parameter names | Exact declared names including `@`; metadata resolves the canonical name |
| Unsupported values | Booleans, objects, and nested arrays; use numeric 0/1 for bits |
| Strings | Converted to escaped Unicode SQL literals, not evaluated as SQL expressions |
| Duplicate values | Retained and executed separately |
| Re-registration | A second domain for the same parameter fails; reset before changing it |
| Omitted parameters | Keep their SQL defaults; missing required parameters produce call errors |
| Scope | Global on both engines; optional session storage on SQL Server only |

For these two recipes the total is 6 + 6 = 12 cases. Run both using a variable
for the combined procedure selection:

- `test.run @test_names` selects both procedures and generates cases from their saved
  dimension domains; with the supplied definitions it executes six cases per test.
- `test.run` reports each combination independently and fails if any check fails;
  it does not clear domains or guarantee an execution order between combinations.

```sql
DECLARE @names nvarchar(max);
SET @names = N'[tests].[replicate@recipe_dimension_tokens]|'
    + N'[tests].[nullif@recipe_dimension_pairs]';
EXEC test.run @test_names = @names;
```

Explicit vectors are added to the dimension cases and execute in the first phase.
For example, two vectors plus a 3 x 2 product produce eight calls, not twelve.
Targeted reset clears both vectors and dimensions for the procedure, avoiding hidden
extra cases when rerunning these recipes. Combination order is not guaranteed;
assert each case independently rather than relying on a previous case.

The runner materializes the full product for a procedure before executing it.
Ten values in six domains already produce 1,000,000 cases. BIGINT overflow checks
and `@max_failures` do not prevent expensive generation. Keep domains small and
choose a few explicit vectors for large or dependent input spaces.

These recipes exercise both NULL assertions and scalar equality across generated
cases. See [static recipes](static-test-recipes.md#assertion-coverage-and-cleanup)
for all eight assertions, and [data recipes](data-test-recipes.md) for FLOAT and
expected-error cases.

## Cleanup

Clear only these procedures' registrations before dropping them. Retain the shared
table; other tests may be using it.

- `test.set_registration_scope N'global'` selects shared storage; targeted `test.clear_registrations` clears only
  these two procedures' vectors and dimensions, preserving the table and other rows.
- `DROP PROCEDURE IF EXISTS` removes the recipe procedures after reset so
  `test.run` no longer discovers them; dropping first would prevent name validation.

```sql
EXEC test.set_registration_scope N'global';
EXEC test.clear_registrations @test_name = N'[tests].[replicate@recipe_dimension_tokens]';
EXEC test.clear_registrations @test_name = N'[tests].[nullif@recipe_dimension_pairs]';
DROP PROCEDURE IF EXISTS [tests].[replicate@recipe_dimension_tokens];
DROP PROCEDURE IF EXISTS [tests].[nullif@recipe_dimension_pairs];
```

On SQL Server, optional session scope requires a caller-created
`#test_dimension_values` table with the same columns, directly in the outer batch.
Then select `session` on that connection. Global domains are not copied into it.
Fabric Warehouse rejects session scope; use coordinated global fixtures instead.
