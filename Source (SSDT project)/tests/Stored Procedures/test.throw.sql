CREATE PROC [tests].[test.throw]
AS
PRINT N'Check THROW, fail and missing-error sentinel helpers.';
PRINT N'Expect: 4 exceptions caught; NULL message stays NULL.';
SET NOCOUNT ON;

DECLARE @result nvarchar(max), @error_result int,
	@proc_id int = OBJECT_ID(N'[tests].[test.throw]');

-- Assert
SET @result = test.throw_error(NULL);
SET @result = test.assert_null(N'NULL error message stays NULL', CONVERT(varbinary(max), @result));

BEGIN TRY
	EXEC test.throw @message = N'Test exception!', @proc_id = @proc_id;
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Thrown exception metadata', 70000,
		N'Test exception!%<Procedure:> [[]tests].[[]test.throw]%', 1);
	IF @error_result IS NOT NULL THROW 51091, 'Matching error metadata must return NULL.', 1;

END CATCH;

BEGIN TRY
	SET @result = test.throw_error(N'basic raw error');
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Raw error must be raised', 245,
		N'%basic raw error%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.fail(N'basic explicit failure');
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Explicit failure must be raised', 245,
		N'%Unit-test fail: basic explicit failure%', DEFAULT);
END CATCH;

-- assert_error deliberately rejects the no-error sentinel.
BEGIN TRY
	SET @result = test.fail_no_error();
	THROW 51091, 'The no-error sentinel did not throw.', 1;
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE N'%<<No error>>%'
		THROW;
END CATCH;
