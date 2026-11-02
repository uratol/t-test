CREATE PROC [tests].[test.assert_null]
AS
PRINT N'Check NULLs, empty scalar SELECTs and empty aggregates.';
PRINT N'Expect: NULLs pass; empty bytes and zero are rejected.';
SET NOCOUNT ON;

DECLARE @empty_value nvarchar(128), @empty_sum int, @empty_count int,
	@null_result nvarchar(max), @nullif_result nvarchar(max),
	@query_result nvarchar(max), @sum_result nvarchar(max),
	@assertion_result nvarchar(max), @error_result int;

-- Arrange
SET @empty_value = (SELECT name FROM sys.tables WHERE 1 = 0);
SELECT @empty_sum = SUM(v.value), @empty_count = COUNT(*)
FROM (VALUES (1)) v(value)
WHERE 1 = 0;

-- Act
SET @null_result = test.assert_null(N'Literal NULL', NULL);
SET @nullif_result = test.assert_null(N'NULLIF returns NULL', CONVERT(varbinary(max), NULLIF(1, 1)));
SET @query_result = test.assert_null(N'Empty scalar SELECT returns NULL', CONVERT(varbinary(max), @empty_value));
SET @sum_result = test.assert_null(N'SUM of an empty set is NULL', CONVERT(varbinary(max), @empty_sum));

-- Assert
SET @assertion_result = test.assert_equals(N'Literal NULL must pass', N'', @null_result);
SET @assertion_result = test.assert_equals(N'NULLIF result must pass', N'', @nullif_result);
SET @assertion_result = test.assert_equals(N'Empty scalar SELECT must pass', N'', @query_result);
SET @assertion_result = test.assert_equals(N'Empty SUM must pass', N'', @sum_result);

BEGIN TRY
	SET @assertion_result = test.assert_null(N'basic non-NULL rejection', 0x);
	SET @assertion_result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Empty bytes are not NULL', 245,
		N'%Unit-test fail: basic non-NULL rejection%', DEFAULT);
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] non-NULL bytes rejected.', 0, 1) WITH NOWAIT;
END CATCH;

BEGIN TRY
	SET @assertion_result = test.assert_null(N'COUNT of an empty set is zero', CONVERT(varbinary(max), @empty_count));
	SET @assertion_result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Zero is not NULL', 245,
		N'%Unit-test fail: COUNT of an empty set is zero%', DEFAULT);
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] zero rejected.', 0, 1) WITH NOWAIT;
END CATCH;
