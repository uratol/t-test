CREATE FUNCTION [test].[assert_float_equals]
( @message nvarchar(max)
, @expected float
, @actual float
, @tolerance float
)
RETURNS nvarchar(max)
AS
BEGIN
	DECLARE @return_value nvarchar(max) = N'', @equal bit = 0;

	IF @tolerance IS NULL OR @tolerance < 0
		SET @return_value = test.fail(CONCAT(@message, CHAR(13), CHAR(10),
			N'Absolute tolerance must be non-negative and not NULL.'));
	ELSE
	BEGIN
		IF @expected IS NULL AND @actual IS NULL
			SET @equal = 1;
		ELSE IF @expected IS NOT NULL AND @actual IS NOT NULL
		BEGIN
			IF (@expected < 0 AND @actual > 0) OR (@expected > 0 AND @actual < 0)
			BEGIN
				-- Subtracting opposite-sign values can overflow FLOAT.
				IF ABS(@actual) <= @tolerance - ABS(@expected)
					AND ABS(@expected) <= @tolerance - ABS(@actual)
					SET @equal = 1;
			END
			ELSE IF ABS(@expected - @actual) <= @tolerance
				SET @equal = 1;
		END;

		IF @equal = 0
			SET @return_value = test.fail(CONCAT(@message, CHAR(13), CHAR(10),
				N'expected: ', COALESCE(N'<' + CONVERT(nvarchar(32), @expected, 3) + N'>', N'null'),
				CHAR(13), CHAR(10),
				N'but was : ', COALESCE(N'<' + CONVERT(nvarchar(32), @actual, 3) + N'>', N'null'),
				CHAR(13), CHAR(10),
				N'absolute tolerance: <', CONVERT(nvarchar(32), @tolerance, 3), N'>'));
	END;

	RETURN @return_value;
END;
