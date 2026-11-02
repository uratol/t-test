CREATE PROC [tests].[test.assert_not_null]
AS
PRINT N'Check non-NULL bytes, empty bytes and NULL.';
PRINT N'Expect: both byte values pass; NULL failure is caught.';
SET NOCOUNT ON;

DECLARE @bytes_result nvarchar(max), @empty_result nvarchar(max),
	@assertion_result nvarchar(max), @error_result int;

-- Act
SET @bytes_result = test.assert_not_null(N'Non-NULL bytes', 0x01);
SET @empty_result = test.assert_not_null(N'Empty bytes are not NULL', 0x);

-- Assert
SET @assertion_result = test.assert_equals(N'Non-NULL bytes must pass', N'', @bytes_result);
SET @assertion_result = test.assert_equals(N'Empty bytes must pass', N'', @empty_result);

-- Act
BEGIN TRY
	SET @bytes_result = test.assert_not_null(N'basic NULL rejection', NULL);
	SET @bytes_result = test.fail_no_error();
END TRY
BEGIN CATCH
	-- Assert
	SET @error_result = test.assert_error(N'NULL must be rejected', 245,
		N'%Unit-test fail: basic NULL rejection%', DEFAULT);
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] NULL rejected.', 0, 1) WITH NOWAIT;
END CATCH;
