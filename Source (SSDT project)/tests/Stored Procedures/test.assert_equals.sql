CREATE PROC [tests].[test.assert_equals]
AS
PRINT N'Check text, NULL, numeric, bit and date equality.';
PRINT N'Expect: equal values pass; text/float mismatches caught.';
SET NOCOUNT ON;

DECLARE @result nvarchar(max), @error_result int;

-- Assert
SET @result = test.assert_equals(N'Equal text', N'value', N'value');
SET @result = test.assert_equals(N'Equal NULLs', NULL, NULL);
SET @result = test.assert_equals(N'Equal integers', CAST(42 AS int), 6 * 7);
SET @result = test.assert_equals(N'Equal big integers',
	CAST(9007199254740993 AS bigint), CAST(9007199254740992 AS bigint) + 1);
SET @result = test.assert_equals(N'Equal decimals',
	CAST(123.125 AS decimal(18, 4)), CAST(123 + 0.125 AS decimal(18, 4)));
SET @result = test.assert_equals(N'Equal floats without tolerance',
	CONVERT(nvarchar(32), 1.25E0, 3), CONVERT(nvarchar(32), 0.5E0 + 0.75E0, 3));
SET @result = test.assert_equals(N'Equal bits', CAST(1 AS bit), CAST(1 AS bit));
SET @result = test.assert_equals(N'Equal dates',
	CAST('2026-03-04' AS date), DATEFROMPARTS(2026, 3, 4));
SET @result = test.assert_equals(N'Success returns empty text', N'', @result);

BEGIN TRY
	SET @result = test.assert_equals(N'basic equality mismatch', N'left', N'right');
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Mismatched values must fail', 245,
		N'%Unit-test fail: basic equality mismatch%expected: <left>%but was : <right>%',
		DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_equals(N'basic exact float mismatch',
		CONVERT(nvarchar(32), 1.25E0, 3), CONVERT(nvarchar(32), 1.2500000000000002E0, 3));
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Different floats must fail without tolerance', 245,
		N'%Unit-test fail: basic exact float mismatch%expected:%but was :%', DEFAULT);
END CATCH;
