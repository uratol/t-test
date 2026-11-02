CREATE PROC [test].[assert_resultset_equals]
	@message nvarchar(max),
	@expected_query nvarchar(max),
	@actual_query nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @expected nvarchar(max), @actual nvarchar(max), @sql nvarchar(max),
		@result nvarchar(max), @whitespace nvarchar(4) = N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13);

	SET @expected_query = TRIM(@whitespace FROM @expected_query);
	SET @actual_query = TRIM(@whitespace FROM @actual_query);
	IF RIGHT(@expected_query, 1) = N';'
		SET @expected_query = TRIM(@whitespace FROM LEFT(@expected_query, LEN(@expected_query) - 1));
	IF RIGHT(@actual_query, 1) = N';'
		SET @actual_query = TRIM(@whitespace FROM LEFT(@actual_query, LEN(@actual_query) - 1));

	IF @expected_query IS NULL OR @expected_query = N''
	BEGIN
		SET @result = test.fail(CONCAT(@message, N': expected query must not be NULL or empty.'));
		RETURN;
	END;
	IF @actual_query IS NULL OR @actual_query = N''
	BEGIN
		SET @result = test.fail(CONCAT(@message, N': actual query must not be NULL or empty.'));
		RETURN;
	END;

	SET @sql = N'SET @json = (' + NCHAR(10) + @expected_query
		+ NCHAR(10) + N'FOR JSON PATH, INCLUDE_NULL_VALUES);';
	EXEC sys.sp_executesql @sql, N'@json nvarchar(max) OUTPUT', @json = @expected OUTPUT;

	SET @sql = N'SET @json = (' + NCHAR(10) + @actual_query
		+ NCHAR(10) + N'FOR JSON PATH, INCLUDE_NULL_VALUES);';
	EXEC sys.sp_executesql @sql, N'@json nvarchar(max) OUTPUT', @json = @actual OUTPUT;

	SET @result = test.assert_equals(@message, @expected, @actual);
END;
