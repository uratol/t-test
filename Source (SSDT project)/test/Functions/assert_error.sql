CREATE FUNCTION [test].[assert_error]
( @message nvarchar(max)
, @expected_number int = NULL
, @expected_message_pattern nvarchar(max) = NULL
, @expected_state int = NULL
)
RETURNS int
AS
BEGIN
	DECLARE @actual_number int = ERROR_NUMBER(), @actual_message nvarchar(max) = ERROR_MESSAGE(),
		@actual_state int = ERROR_STATE(), @return_value int;

	IF @actual_number IS NULL OR @actual_message LIKE N'%<<No error>>%'
		SET @return_value = test.fail(CONCAT(@message, N'. Expected a caught error; none was caught.'));
	ELSE IF (@expected_number IS NOT NULL AND @actual_number IS DISTINCT FROM @expected_number)
		OR (@expected_message_pattern IS NOT NULL
			AND (@actual_message IS NULL OR @actual_message NOT LIKE @expected_message_pattern))
		OR (@expected_state IS NOT NULL AND @actual_state IS DISTINCT FROM @expected_state)
		SET @return_value = test.fail(CONCAT(@message,
			N'. Expected error number: ', COALESCE(CONVERT(nvarchar(12), @expected_number), N'<any>'),
			N'; message pattern: ', COALESCE(N'<' + @expected_message_pattern + N'>', N'<any>'),
			N'; state: ', COALESCE(CONVERT(nvarchar(12), @expected_state), N'<any>'),
			N'. Got error number: ', @actual_number,
			N'; message: <', @actual_message, N'>; state: ', @actual_state, N'.'));

	RETURN @return_value;
END;
