-- Install 16 framework self-tests and their standard global vectors.
-- Run install.sql first, then this entire file including every GO.
-- Does not execute tests or create the runner's disposable scenario fixtures.
-- Execute run-framework-coverage-tests.sql separately to run the 49 scenario groups.
-- Framework self-tests keep independent IF/THROW checks in Assert.
SET NOCOUNT ON;
-- Preserve the preflight guard across GO so later batches cannot deploy after rejection.
DROP TABLE IF EXISTS #fc_run;
CREATE TABLE #fc_run (ready bit);
INSERT #fc_run VALUES (0);
IF @@TRANCOUNT > 0
    THROW 51090, 'Install framework tests outside a transaction.', 1;
IF OBJECT_ID(N'test.run', N'P') IS NULL OR OBJECT_ID(N'test.is_equal', N'FN') IS NULL
    OR OBJECT_ID(N'test.fail_no_error', N'P') IS NULL
    OR OBJECT_ID(N'test.assert_error', N'P') IS NULL
    OR OBJECT_ID(N'test.set_registration_scope', N'P') IS NULL
    OR OBJECT_ID(N'test.vector', N'P') IS NULL
    OR OBJECT_ID(N'test.test_vectors', N'U') IS NULL
    THROW 51090, 'Install the framework before installing its coverage tests.', 1;
UPDATE #fc_run SET ready = 1;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.is_equal@fc_values]
AS
PRINT N''Compare strings, NULLs, numbers and ordered JSON.'';
PRINT N''Expect: row order/types matter; column order does not.'';

DECLARE @cases nvarchar(max), @i int, @n int,
	@l nvarchar(max), @r nvarchar(max), @expected bit, @actual bit, @name nvarchar(100),
	@message nvarchar(2048);

-- Arrange
SET @i = 0;
SET @cases = N''[
 {"name":"nulls","l":null,"r":null,"eq":1},
 {"name":"null/string","l":null,"r":"","eq":0},
 {"name":"equal strings","l":"hello","r":"hello","eq":1},
 {"name":"different strings","l":"hello","r":"world","eq":0},
 {"name":"numeric spelling","l":"001.50","r":"1.5","eq":1},
 {"name":"scalar tiny decimal","l":"0.000000000000000000001","r":"0","eq":0},
 {"name":"scalar negative tiny decimal","l":"-0.000000000000000000001","r":"0","eq":0},
 {"name":"scalar precise decimal","l":"1.000000000000000000001","r":"1.000000000000000000002","eq":0},
 {"name":"scalar decimal rounding boundary","l":"0.000000000000000000005","r":"0.00000000000000000001","eq":0},
 {"name":"scalar decimal truncated tail","l":"0.1234567890123456789012","r":"0.12345678901234567890","eq":0},
 {"name":"scalar lossy alternative spelling","l":"0.0000000000000000000012","r":"0.00000000000000000000120","eq":0},
 {"name":"lossless decimal boundary","l":"09999999999.99999999999999999999","r":"9999999999.99999999999999999999","eq":1},
 {"name":"scalar negative zero","l":"-0","r":"0","eq":1},
 {"name":"scalar leading plus","l":"+1","r":"1","eq":1},
 {"name":"scalar surrounding spaces","l":" 1 ","r":"1","eq":1},
 {"name":"scalar omitted integer zero","l":".5","r":"0.5","eq":1},
 {"name":"scalar scientific notation unsupported","l":"1e2","r":"100","eq":0},
 {"name":"scalar integer range boundary","l":"10000000000","r":"10000000000.0","eq":0},
 {"name":"raw exponent spelling","l":"[1,1.0,1e0]","r":"[1.000,1e+0,1]","eq":0},
 {"name":"raw negative exponent","l":"[-1.25e-4]","r":"[-0.000125]","eq":0},
 {"name":"raw large exponent","l":"[1e1000]","r":"[10e999]","eq":0},
 {"name":"raw exponent above BIGINT","l":"[1e9223372036854775808]","r":"[10e9223372036854775807]","eq":0},
 {"name":"raw exponent below BIGINT","l":"[1e-9223372036854775809]","r":"[0.1e-9223372036854775808]","eq":0},
 {"name":"raw zero spelling","l":"[-0e99999999999999999999999999999]","r":"[0]","eq":0},
 {"name":"raw numeric sequence","l":"[10e99,0.1e-99,-0,12.3400]","r":" [10e99,0.1e-99,-0,12.3400]","eq":1},
 {"name":"tiny nonzero number","l":"[1e-1000]","r":"[0]","eq":0},
 {"name":"exact high precision","l":"[0.123456789012345678901]","r":"[0.123456789012345678902]","eq":0},
 {"name":"negative zero spelling","l":"[-0,0e1000]","r":"[0,0.0]","eq":0},
 {"name":"different numbers","l":"1","r":"2","eq":0},
 {"name":"object order","l":"{\"a\":1,\"b\":2}","r":"{\"b\":2,\"a\":1}","eq":1},
 {"name":"array order","l":"[1,2,3]","r":"[3,1,2]","eq":0},
 {"name":"multiplicity","l":"[1,1,2]","r":"[1,2,2]","eq":0},
 {"name":"empty containers","l":"{}","r":"[]","eq":0},
 {"name":"null property","l":"{\"a\":null}","r":"{}","eq":0},
 {"name":"number/string types","l":"[1]","r":"[\"1\"]","eq":0},
 {"name":"boolean/number types","l":"[true]","r":"[1]","eq":0},
 {"name":"column order","l":"[{\"id\":1,\"value\":\"a\"},{\"id\":2,\"value\":\"b\"}]","r":"[{\"value\":\"a\",\"id\":1},{\"value\":\"b\",\"id\":2}]","eq":1},
 {"name":"row order","l":"[{\"id\":1,\"value\":\"a\"},{\"id\":2,\"value\":\"b\"}]","r":"[{\"value\":\"b\",\"id\":2},{\"value\":\"a\",\"id\":1}]","eq":0},
 {"name":"row association","l":"[{\"id\":1,\"value\":\"a\"},{\"id\":2,\"value\":\"b\"}]","r":"[{\"id\":1,\"value\":\"b\"},{\"id\":2,\"value\":\"a\"}]","eq":0},
 {"name":"duplicate rows","l":"[{\"id\":1},{\"id\":1}]","r":"[{\"id\":1}]","eq":0},
 {"name":"empty row","l":"[{}]","r":"[]","eq":0},
 {"name":"NULL column versus absent column","l":"[{\"id\":null}]","r":"[{}]","eq":0},
 {"name":"raw date spelling","l":"[\"2026-03-04\"]","r":"[\"2026-03-04T00:00:00\"]","eq":0},
 {"name":"unicode/control","l":"[\"\\u017d\\n\\t\"]","r":"[\"\\u017d\\n\\t\"]","eq":1},
 {"name":"invalid JSON strings","l":"{bad","r":"{different","eq":0}
]'';
SET @n = (SELECT COUNT(*) FROM OPENJSON(@cases));

-- Shortcuts must not evaluate JSON parsing.
-- Act
SET @actual = test.is_equal(NULL, N'''');

-- Assert
IF @actual IS DISTINCT FROM 0 THROW 51091, ''Literal NULL/string comparison evaluated JSON parsing.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N''{bad JSON'', N''{bad JSON'');

-- Assert
IF @actual IS DISTINCT FROM 1 THROW 51091, ''Equal literal strings evaluated JSON parsing.'', 1;

WHILE @i < @n
BEGIN
	-- Arrange
	SELECT @l = l, @r = r, @expected = eq, @name = name
	FROM OPENJSON(@cases, CONCAT(''$['', @i, '']''))
	WITH (name nvarchar(100), l nvarchar(max), r nvarchar(max), eq bit);

	-- Act
	SET @actual = test.is_equal(@l, @r);

	-- Assert
	IF @actual IS DISTINCT FROM @expected
	BEGIN
		SET @message = N''is_equal scenario failed: '' + @name;
		THROW 51091, @message, 1;
	END;
	SET @i += 1;
END;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	EXEC(N'CREATE OR ALTER PROC [tests].[test.is_json_equal@fc_json]
AS
PRINT N''Compare long JSON values, Unicode and escape forms.'';
PRINT N''Expect: no truncation; equivalent decoded text matches.'';

DECLARE @text nvarchar(max), @left nvarchar(max), @right nvarchar(max), @equal bit,
	@unicode nvarchar(max);

-- Arrange
SET @text = REPLICATE(CAST(N''x'' AS nvarchar(max)), 6000);
SET @left = JSON_OBJECT(''text'': @text, ''id'': 1);
SET @right = JSON_OBJECT(''id'': 1, ''text'': @text);

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 1 THROW 51091, ''Long JSON values or column ordering failed.'', 1;

-- Arrange
SET @right = JSON_OBJECT(''id'': 1, ''text'': @text + N''y'');

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 0 THROW 51091, ''Long JSON values were truncated.'', 1;

-- Arrange
SET @unicode = NCHAR(0x0416) + NCHAR(0x4E2D)
	+ CONVERT(nvarchar(2), 0x3DD800DE);
SET @left = JSON_ARRAY(@unicode);
SET @right = N''["\u0416\u4e2d\ud83d\ude00"]'';

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 1 THROW 51091, ''Raw and escaped Unicode differ.'', 1;

-- Arrange
SET @left = JSON_ARRAY(NCHAR(8) + NCHAR(12) + NCHAR(10)
	+ NCHAR(13) + NCHAR(9) + N''/\"'');
SET @right = N''["\b\f\n\r\t\/\\\""]'';

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 1 THROW 51091, ''JSON escape decoding differs.'', 1;');
	DROP PROCEDURE IF EXISTS [tests].[test.is_equal_openjson@fc_json];
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_equals@fc_assertions]
AS
PRINT N''Check equality/NULL assertions and 3 failure cases.'';
PRINT N''Expect: valid checks pass; all 3 failures are caught.'';

DECLARE @caught bit, @i int, @message nvarchar(max);

-- Arrange
SET @i = 0;

-- Act
EXEC test.assert_equals N''equal'', N''1.0'', N''1'';
EXEC test.assert_null N''null'', NULL;
EXEC test.assert_not_null N''not null'', 0x;

-- Assert
-- Successful return of the valid assertions is checked by the positive-suite summary.

WHILE @i < 3
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 EXEC test.assert_equals N''fc assertion marker'', N''a'', N''b'';
		ELSE IF @i = 1 EXEC test.assert_null N''fc assertion marker'', 0x01;
		ELSE EXEC test.assert_not_null N''fc assertion marker'', NULL;
	END TRY
	BEGIN CATCH
		-- Assert
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''Unit-test fail:'', @message) > 0
			AND CHARINDEX(N''fc assertion marker'', @message) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''A failing assertion did not raise its failure marker.'', 1;
	SET @i += 1;
END;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.throw_error@fc_error_helpers]
AS
PRINT N''Check error helpers and numeric/empty messages.'';
PRINT N''Expect: NULL stays NULL; 11 invalid calls are caught.'';

DECLARE @result nvarchar(max), @caught bit, @i int, @message nvarchar(max),
	@numeric_messages nvarchar(max), @number_message nvarchar(max);

-- Arrange
SET @i = 0;
SET @numeric_messages = N''["123",""," ","-2","+3","0004","2147483647","-2147483648"]'';

-- Act
SET @result = test.throw_error(NULL);

-- Assert
IF @result IS NOT NULL THROW 51091, ''throw_error(NULL) must return NULL.'', 1;

WHILE @i < 3
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 SET @result = test.throw_error(N''fc raw error'');
		ELSE IF @i = 1 SET @result = test.fail(N''fc explicit fail'');
		ELSE EXEC test.fail_no_error;
	END TRY
	BEGIN CATCH
		-- Assert
		SET @message = ERROR_MESSAGE();
		IF (ERROR_NUMBER() = 245 AND (
			(@i = 0 AND CHARINDEX(N''fc raw error'', @message) > 0) OR
			(@i = 1 AND CHARINDEX(N''Unit-test fail: fc explicit fail'', @message) > 0)))
			OR (@i = 2 AND ERROR_NUMBER() = 70001
				AND @message LIKE N''Unit-test fail: <<No error>>%'') SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''An error/fail helper did not throw the expected marker.'', 1;
	SET @i += 1;
END;

SET @i = 0;
WHILE @i < 8
BEGIN
	-- Arrange
	SELECT @number_message = value FROM OPENJSON(@numeric_messages) WHERE [key] = CONVERT(nvarchar(10), @i);
	SET @caught = 0;

	-- Act
	BEGIN TRY
		SET @result = test.throw_error(@number_message);
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Error: '', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''A numeric or empty raw error message did not throw.'', 1;
	SET @i += 1;
END;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_null@fc_null]
AS
PRINT N''Check that assert_null accepts only NULL.'';
PRINT N''Expect: NULL passes; the non-NULL failure is caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
EXEC test.assert_null N''NULL is NULL'', NULL;

BEGIN TRY
	EXEC test.assert_null N''fc empty binary is not NULL'', 0x;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc empty binary is not NULL'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''assert_null accepted an empty non-NULL value.'', 1;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_not_null@fc_not_null]
AS
PRINT N''Check that assert_not_null rejects only NULL.'';
PRINT N''Expect: zero bytes pass; the NULL failure is caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
EXEC test.assert_not_null N''zero bytes are not NULL'', 0x0000;

BEGIN TRY
	EXEC test.assert_not_null N''fc NULL must fail'', NULL;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc NULL must fail'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''assert_not_null accepted NULL.'', 1;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.fail@fc_failure]
AS
PRINT N''Call fail() with a numeric message and with NULL.'';
PRINT N''Expect: both calls throw; both exceptions are caught.'';

DECLARE @result int, @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	SET @result = test.fail(N''123'');
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Unit-test fail: 123'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''fail did not reject a numeric-only message.'', 1;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	SET @result = test.fail(NULL);
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Unit-test fail:'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''fail(NULL) did not raise a failure.'', 1;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	EXEC(N'CREATE OR ALTER PROC [tests].[test.fail_no_error@fc_no_error]
AS
PRINT N''Call fail_no_error after an expected error is missing.'';
PRINT N''Expect: its no-error marker is raised and caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 70001 AND ERROR_MESSAGE() LIKE N''Unit-test fail: <<No error>>%'' SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''fail_no_error did not raise its no-error marker.'', 1;');
	DROP PROCEDURE IF EXISTS [tests].[test.error@fc_no_error];
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_error@fc_patterns]
AS
PRINT N''Check error LIKE patterns and the no-error marker.'';
PRINT N''Expect: matching passes; the invalid match is caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	THROW 51011, ''fc wildcard_value'', 1;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N''literal underscore and wildcard'', DEFAULT, N''fc wildcard[_]%'', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	BEGIN TRY
		EXEC test.assert_error N''fc no-error marker must be rejected'', DEFAULT, N''%<<No error>>%'', DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc no-error marker must be rejected'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
END CATCH;

IF @caught = 0 THROW 51091, ''assert_error accepted the no-error marker.'', 1;');
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error_like@fc_patterns];
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_error@fc_error_assertions]
AS
PRINT N''Check matching/mismatching error numbers and patterns.'';
PRINT N''Expect: matches pass; invalid checks throw and are caught.'';

DECLARE @caught bit, @value int, @i int;

-- Arrange
SET @caught = 0;

-- A real conversion error must still be accepted.
-- Act
BEGIN TRY
	SET @value = CONVERT(int, N''fc genuine conversion error'');
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() <> 245 THROW;
	EXEC test.assert_error N''genuine conversion error'', 245, DEFAULT, DEFAULT;
	SET @caught = 1;
END CATCH;

IF @caught = 0
	THROW 51091, ''A genuine conversion error was not accepted.'', 1;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	THROW 51011, ''fc expected exception'', 1;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N''matching number'', 51011, DEFAULT, DEFAULT;
	EXEC test.assert_error N''matching pattern'', DEFAULT, N''%fc expected exception%'', DEFAULT;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N''fc wrong number'', 51012, DEFAULT, DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc wrong number'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''Wrong error number was accepted.'', 1;

	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		EXEC test.assert_error N''fc wrong pattern'', DEFAULT, N''%not the actual message%'', DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc wrong pattern'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''Wrong error pattern was accepted.'', 1;
END CATCH;
-- The no-error sentinel must NOT satisfy even its matching native error number.
-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	BEGIN TRY
		EXEC test.assert_error N''fc sentinel is not a real conversion error'', 70001, DEFAULT, DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(
			N''Unit-test fail: fc sentinel is not a real conversion error'', ERROR_MESSAGE()) > 0
			SET @caught = 1;
	END CATCH;
END CATCH;

IF @caught = 0 THROW 51091, ''Error number assertion accepted the no-error sentinel.'', 1;
SET @i = 0;
WHILE @i < 2
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 EXEC test.assert_error N''fc no active error'', 51011, DEFAULT, DEFAULT;
		ELSE EXEC test.assert_error N''fc no active error'', DEFAULT, N''%anything%'', DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc no active error'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''An error assertion passed outside CATCH.'', 1;
	SET @i += 1;
END;');
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error_number@fc_error_assertions];
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.format_message@fc_parameters]
AS
PRINT N''Check placeholders, Unicode and explicit ISO/hex text.'';
PRINT N''Expect: exact text, NULLs and repeated placeholders.'';

DECLARE @actual nvarchar(max), @date datetime2(6), @date_text nvarchar(33), @hex nvarchar(4000),
	@raw_date sql_variant, @raw_binary sql_variant, @plain nvarchar(max);

-- Arrange
SET @date = CAST(''2026-03-04T05:06:07.123456'' AS datetime2(6));
SET @hex = CONVERT(nvarchar(4000), 0xAB, 1);
SET @date_text = CONVERT(nvarchar(33), @date, 126);

-- Each parameter arrangement has its own exact reference.
-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', @date_text, CONVERT(nvarchar(4000), 0x010203, 1), 42, NULL);

-- Assert
IF @actual IS DISTINCT FROM N''2026-03-04T05:06:07.123456|0x010203|42|<null>''
	THROW 51091, ''Explicit ISO/hex/numeric/NULL substitution failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', NULL, 42, @hex, @date_text);

-- Assert
IF @actual IS DISTINCT FROM N''<null>|42|0xAB|2026-03-04T05:06:07.123456''
	THROW 51091, ''Formatting in alternate parameter positions failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', 42, @date_text, NULL, @hex);

-- Assert
IF @actual IS DISTINCT FROM N''42|2026-03-04T05:06:07.123456|<null>|0xAB''
	THROW 51091, ''Second date/fourth binary parameter formatting failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', @hex, NULL, @date_text, 42);

-- Assert
IF @actual IS DISTINCT FROM N''0xAB|<null>|2026-03-04T05:06:07.123456|42''
	THROW 51091, ''Third date/first binary parameter formatting failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', DEFAULT, DEFAULT, DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''%1|%2|%3|%4'' THROW 51091, ''Unassigned placeholders changed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2'', N''10/31/26'', N''0xabcdef'', DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''10/31/26|0xabcdef'' THROW 51091, ''Text was reclassified as date/binary.'', 1;

-- Arrange
SET @date = CAST(''2026-03-04T00:00:00'' AS datetime2(6));

-- Act
SET @actual = test.format_message(N''%1'', CONVERT(nvarchar(33), @date, 126), DEFAULT, DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''2026-03-04T00:00:00'' THROW 51091, ''ISO midnight text changed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2'', CONVERT(nvarchar(4000), 0x, 1),
	CONVERT(nvarchar(33), CAST(NULL AS datetime2(6)), 126), DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''0x|<null>'' THROW 51091, ''Empty hex or NULL ISO substitution failed.'', 1;

-- Arrange
SET @raw_date = @date;
SET @raw_binary = 0x41004200;
SET @plain = CONCAT(CAST(@raw_date AS nvarchar(4000)), N''|'', CAST(@raw_binary AS nvarchar(4000)));

-- Act
SET @actual = test.format_message(N''%1|%2'', @raw_date, @raw_binary, DEFAULT, DEFAULT);

-- Assert
IF CONVERT(varbinary(max), @actual) IS DISTINCT FROM CONVERT(varbinary(max), @plain)
	THROW 51091, ''Formatter still applies implicit date/binary formatting.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(NULL, 1, 2, 3, 4);

-- Assert
IF @actual IS NOT NULL THROW 51091, ''NULL message changed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1:%1:100%'', NCHAR(381), DEFAULT, DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM NCHAR(381) + N'':'' + NCHAR(381) + N'':100%''
	THROW 51091, ''Unicode/repeated placeholder/percent formatting failed.'', 1;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.log@fc_logging]
AS
PRINT N''Check logger levels, parameters and chunked output.'';
PRINT N''Expect: sample WARNING/DEBUG logs; all 4100 chars printed.'';

DECLARE @id int, @data nvarchar(max), @multiline nvarchar(max), @hex nvarchar(4000),
	@boundary nvarchar(max);

-- Arrange
SET @id = OBJECT_ID(N''[tests].[test.log@fc_logging]'');
SET @data = REPLICATE(CAST(N''x'' AS nvarchar(max)), 4100);
SET @multiline = N''first'' + NCHAR(13) + NCHAR(10) + N''second'';
SET @hex = CONVERT(nvarchar(4000), 0x0102, 1);
SET @boundary = REPLICATE(CAST(N''x'' AS nvarchar(max)), 2040) + N''%'';
-- SQL cannot capture PRINT/InfoMessage text: these are explicit output-path smoke checks.

-- Act
EXEC test.log @message = NULL, @data = NULL;
EXEC test.log @message = N''fc logger %1 %2 %3 %4 100%'', @p1 = 42, @p2 = NULL,
	@p3 = @hex, @p4_str = N''wide text'', @rowcount = 0, @proc_id = @id, @severity = N''warning'';
EXEC test.log @message = N''fc inline data'', @data = N''short 100% data'', @severity = N''info'';
EXEC test.log @message = N''fc multiline data'', @data = @multiline;
EXEC test.log @message = N''fc chunked data (4100 characters)'', @data = @data;

-- A literal percent at a truncation boundary must not become a format token.
EXEC test.log @message = @boundary;
EXEC test.log @message = N''fc boundary data'', @data = @boundary;

-- Assert
-- Successful return is verified by the positive-suite runner summary below.
');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.throw@fc_throwing]
AS
PRINT N''Throw 3 exceptions: no ID, valid ID, invalid ID.'';
PRINT N''Expect: all 3 caught; message and procedure ID verified.'';

DECLARE @id int, @caught bit, @i int, @message nvarchar(max), @scenario nvarchar(128);

SET @id = OBJECT_ID(N''[tests].[test.throw@fc_throwing]'');
SET @i = 0;
WHILE @i < 3
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 EXEC test.throw @message = N''fc thrown exception'';
		ELSE IF @i = 1 EXEC test.throw @message = N''fc thrown exception'', @proc_id = @id;
		ELSE EXEC test.throw @message = N''fc thrown exception'', @proc_id = -1;
	END TRY
	BEGIN CATCH
		-- Assert
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 70000 AND CHARINDEX(N''fc thrown exception'', @message) = 1
			AND ((@i = 0 AND @message = N''fc thrown exception'')
				OR (@i = 1 AND CHARINDEX(N''[tests].[test.throw@fc_throwing]'', @message) > 0)
				OR (@i = 2 AND CHARINDEX(N''<Procedure:> -1'', @message) > 0)) SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''throw code/message/procedure annotation changed.'', 1;
	SET @scenario = CASE @i
		WHEN 0 THEN N''no procedure ID supplied''
		WHEN 1 THEN N''valid procedure ID; name resolved''
		ELSE N''invalid procedure ID (-1); numeric fallback verified''
	END;
	RAISERROR(''[CAUGHT EXPECTED EXCEPTION] %s: %s'', 0, 1, @scenario, @message) WITH NOWAIT;
	SET @i += 1;
END;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.test@fc_catalog]
AS
PRINT N''Check discovery, name parsing and invalid test names.'';
PRINT N''Expect: valid names parse; malformed names are rejected.'';
SET NOCOUNT ON;
IF @@TRANCOUNT > 0 THROW 51091, ''Catalog self-test requires no active transaction.'', 1;

DECLARE @invalid_one bit, @invalid_two bit, @invalid_three bit, @naming_error nvarchar(max),
	@schema nvarchar(128), @object nvarchar(128), @action nvarchar(128), @main nvarchar(128),
	@conceptual_count int;

-- Arrange
SET @invalid_one = 0;
SET @invalid_two = 0;
SET @invalid_three = 0;
IF OBJECT_ID(N''[tests].[fc_catalog_invalid]'') IS NOT NULL
	OR OBJECT_ID(N''[tests].[fc_catalog_invalid@]'') IS NOT NULL
	OR OBJECT_ID(N''[tests].[@fc_catalog_invalid]'') IS NOT NULL
	THROW 51091, ''Catalog fixture name already exists.'', 1;
BEGIN TRY
BEGIN TRAN;
EXEC(N''CREATE PROC [tests].[test.run@fc_catalog_probe] AS RETURN 0;'');
EXEC(N''CREATE PROC [tests].[fc_catalog_concept@fc_catalog_probe] AS RETURN 0;'');
EXEC(N''CREATE PROC [tests].[fc_catalog_concept@fc_catalog_probe.with.dot] AS RETURN 0;'');

-- Discovery must preserve both conceptual actions.
-- Act
SET @conceptual_count = (SELECT COUNT(*) FROM test.test
	WHERE test_proc_name IN (N''fc_catalog_concept@fc_catalog_probe'', N''fc_catalog_concept@fc_catalog_probe.with.dot'')
		AND tested_object_schema_name IS NULL AND tested_object_full_name IS NULL
		AND tested_object_main_schema_name IS NULL AND tested_object_name = N''fc_catalog_concept''
		AND tested_action = STUFF(test_proc_name, 1, CHARINDEX(''@'', test_proc_name), N''''));

-- Assert
IF @conceptual_count <> 2
	THROW 51091, ''Conceptual discovery must preserve the object/action without assigning a schema.'', 1;
EXEC [tests].[test.test@name_convention];

-- Arrange
EXEC(N''CREATE PROC [tests].[private.test.run@fc_catalog_probe] AS RETURN 0;'');
EXEC(N''CREATE PROC [tests].[test.log@fc_catalog_probe]]edge@extra] AS RETURN 0;'');

-- Act
SELECT @schema = tested_object_schema_name, @object = tested_object_name,
	@action = tested_action, @main = tested_object_main_schema_name
FROM test.test WHERE test_proc_full_name = N''[tests].[test.run@fc_catalog_probe]'';

-- Assert
IF @schema IS DISTINCT FROM N''test'' OR @object IS DISTINCT FROM N''run''
	OR @action IS DISTINCT FROM N''fc_catalog_probe'' OR @main IS DISTINCT FROM N''test''
	THROW 51091, ''Regular discovery/name parsing failed.'', 1;

-- Arrange
--N/A

-- Act
SELECT @schema = tested_object_schema_name, @object = tested_object_name, @main = tested_object_main_schema_name
FROM test.test WHERE test_proc_full_name = N''[tests].[private.test.run@fc_catalog_probe]'';

-- Assert
IF @schema IS DISTINCT FROM N''private'' OR @object IS DISTINCT FROM N''test.run'' OR @main IS DISTINCT FROM N''test''
	THROW 51091, ''Private-schema main-schema parsing failed.'', 1;

-- Arrange
SET @action = NULL;

-- Act
SELECT @action = tested_action FROM test.test
WHERE test_proc_full_name = N''[tests].[test.log@fc_catalog_probe]]edge@extra]'';

-- Assert
IF @action IS DISTINCT FROM N''fc_catalog_probe]edge@extra''
	THROW 51091, ''Bracket escaping or multiple action separators failed.'', 1;
ROLLBACK;

-- UDF assertion errors can doom an explicit transaction, so run invalid-name probes outside it.
-- Arrange
EXEC(N''CREATE PROC [tests].[fc_catalog_invalid] AS RETURN 0;'');
SET @invalid_one = 1;
EXEC(N''CREATE PROC [tests].[fc_catalog_invalid@] AS RETURN 0;'');
SET @invalid_two = 1;
EXEC(N''CREATE PROC [tests].[@fc_catalog_invalid] AS RETURN 0;'');
SET @invalid_three = 1;

-- Act
BEGIN TRY
	EXEC [tests].[test.test@name_convention];
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() <> 245 THROW;
	SET @naming_error = ERROR_MESSAGE();
END CATCH;

IF @naming_error IS NULL
	OR CHARINDEX(N''[tests].[fc_catalog_invalid]'', @naming_error) = 0
	OR CHARINDEX(N''[tests].[fc_catalog_invalid@]'', @naming_error) = 0
	OR CHARINDEX(N''[tests].[@fc_catalog_invalid]'', @naming_error) = 0
	THROW 51091, ''Naming validation must reject malformed conceptual names.'', 1;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;
	IF @invalid_one = 1 DROP PROC [tests].[fc_catalog_invalid];
	IF @invalid_two = 1 DROP PROC [tests].[fc_catalog_invalid@];
	IF @invalid_three = 1 DROP PROC [tests].[@fc_catalog_invalid];
	THROW;
END CATCH;

-- Cleanup is required on success and on unexpected validator errors.
DROP PROC [tests].[fc_catalog_invalid];
DROP PROC [tests].[fc_catalog_invalid@];
DROP PROC [tests].[@fc_catalog_invalid];');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.set_registration_scope@fc_context]
AS
PRINT N''Check mutable session/global scope in SESSION_CONTEXT.'';
PRINT N''Expect: exact values; invalid input preserves the last scope.'';
SET NOCOUNT ON;
DECLARE @session_rejected bit = 0;
DECLARE @previous sql_variant,
	@actual sql_variant, @actual_type nvarchar(128), @scope nvarchar(max), @i int = 0, @caught bit,
	@scopes nvarchar(max) = N''["session","global","session","global"]'',
	@invalid nvarchar(max) = N''[null,"","GLOBAL","SESSION","global ","session "]'';
IF CAST(SERVERPROPERTY(''EngineEdition'') AS int) = 11
BEGIN
	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.set_registration_scope N''session'';
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() <> 70000 THROW;
		SET @session_rejected = 1;
	END CATCH;

	IF @session_rejected = 0 THROW 51091, ''Fabric Warehouse accepted session scope.'', 1;
	EXEC test.set_registration_scope N''global'';
	PRINT N''SKIP: mutable session scope is not available on Fabric Warehouse.'';
	RETURN;
END;
SELECT @previous = SESSION_CONTEXT(N''ttest:vectors:scope'');
BEGIN TRY
	WHILE @i < 4
	BEGIN
		-- Arrange
		SELECT @scope = value FROM OPENJSON(@scopes) WHERE CONVERT(int, [key]) = @i;

		-- Act
		EXEC test.set_registration_scope @scope;
		SELECT @actual = SESSION_CONTEXT(N''ttest:vectors:scope'');
		EXEC sys.sp_executesql
			N''SELECT @actual_type = CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@actual, N''''BaseType''''));'',
			N''@actual sql_variant, @actual_type nvarchar(128) OUTPUT'',
			@actual = @actual, @actual_type = @actual_type OUTPUT;

		-- Assert
		IF CONVERT(nvarchar(4000), @actual) COLLATE Latin1_General_100_BIN2
				IS DISTINCT FROM @scope COLLATE Latin1_General_100_BIN2
			OR DATALENGTH(CONVERT(nvarchar(4000), @actual)) IS DISTINCT FROM DATALENGTH(@scope)
			OR @actual_type IS DISTINCT FROM N''nvarchar''
			THROW 51091, ''set_registration_scope did not store the exact mutable Unicode scope.'', 1;
		SET @i += 1;
	END;
	SET @i = 0;
	WHILE @i < (SELECT COUNT(*) FROM OPENJSON(@invalid))
	BEGIN
		-- Arrange
		SELECT @scope = value FROM OPENJSON(@invalid) WHERE CONVERT(int, [key]) = @i;
		SET @caught = 0;

		-- Act
		BEGIN TRY
			EXEC test.set_registration_scope @scope;
		END TRY
		BEGIN CATCH
			-- Assert
			IF ERROR_NUMBER() <> 70000 THROW;
			SET @caught = 1;
		END CATCH;

		SELECT @actual = SESSION_CONTEXT(N''ttest:vectors:scope'');
		IF @caught = 0 OR CONVERT(nvarchar(4000), @actual)
			COLLATE Latin1_General_100_BIN2 IS DISTINCT FROM N''global''
			THROW 51091, ''Invalid scope was accepted or changed SESSION_CONTEXT.'', 1;
		SET @i += 1;
	END;
END TRY
BEGIN CATCH
	EXEC sys.sp_set_session_context @key = N''ttest:vectors:scope'', @value = @previous;
	THROW;
END CATCH;
EXEC sys.sp_set_session_context @key = N''ttest:vectors:scope'', @value = @previous;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	IF OBJECT_ID(N'test.test_vectors', N'U') IS NOT NULL
		EXEC(N'UPDATE test.test_vectors
			SET procedure_name = ''[tests].[test.set_registration_scope@fc_context]''
			WHERE procedure_name = ''[tests].[test.set_scope@fc_context]'';');
	IF OBJECT_ID(N'test.test_dimension_values', N'U') IS NOT NULL
		EXEC(N'UPDATE test.test_dimension_values
			SET procedure_name = ''[tests].[test.set_registration_scope@fc_context]''
			WHERE procedure_name = ''[tests].[test.set_scope@fc_context]'';');
	DROP PROCEDURE IF EXISTS [tests].[test.set_scope@fc_context];
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.vector@fc_literals]
	@case_id int = 0,
	@number bigint = 7,
	@amount decimal(18,4) = 1.5000,
	@approx float = 1.25e0,
	@flag bit = 1,
	@text nvarchar(max) = N''default'',
	@day date = ''20260304'',
	@stamp datetime2(6) = ''2026-03-04T05:06:07.123456'',
	@bytes varbinary(8) = 0x01
AS
PRINT N''Check typed vector arguments, Unicode, NULL and DEFAULT.'';
PRINT N''Expect: SQL preserves values across positional/named literal arguments.'';
SET NOCOUNT ON;

DECLARE @matches bit;

-- Arrange
--N/A

-- Act
SET @matches = CASE WHEN EXISTS (
	SELECT 1
	FROM (VALUES
		(0, CAST(7 AS bigint), CAST(1.5000 AS decimal(18,4)), CAST(1.25 AS float),
			CAST(1 AS bit), CAST(N''default'' AS nvarchar(max)), CAST(''20260304'' AS date),
			CAST(''2026-03-04T05:06:07.123456'' AS datetime2(6)), CAST(0x01 AS varbinary(8))),
		(1, CAST(-9223372036854775808 AS bigint), -1234.5678, -0.000125,
			1, N''O''''Brien, Jr.'', CAST(''20240229'' AS date),
			CAST(''2024-02-29T01:02:03.123456'' AS datetime2(6)), 0x00FF),
		(2, CAST(9223372036854775807 AS bigint), 0.0001, 1250.0,
			0, NCHAR(381) + NCHAR(0x4E2D) + N'', O''''Brien\path'', CAST(''20261231'' AS date),
			CAST(''2026-12-31T23:59:59.999999'' AS datetime2(6)), 0x),
		(3, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
		(4, 0, 0.0000, 0.0, 0, N'''', NULL, NULL, 0x)
	) expected(case_id, number, amount, approx, flag, text_value, day_value, stamp, bytes)
	WHERE @case_id = expected.case_id
		AND @number IS NOT DISTINCT FROM expected.number
		AND @amount IS NOT DISTINCT FROM expected.amount
		AND @approx IS NOT DISTINCT FROM expected.approx
		AND @flag IS NOT DISTINCT FROM expected.flag
		AND CONVERT(varbinary(max), @text) IS NOT DISTINCT FROM CONVERT(varbinary(max), expected.text_value)
		AND @day IS NOT DISTINCT FROM expected.day_value
		AND @stamp IS NOT DISTINCT FROM expected.stamp
		AND @bytes IS NOT DISTINCT FROM expected.bytes
) THEN 1 ELSE 0 END;

-- Assert
IF @matches IS DISTINCT FROM 1
	THROW 51091, ''Typed vector arguments differed from the independent expected values.'', 1;');
GO
IF NOT EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
    DROP TABLE #fc_run;
    THROW 51090, 'Framework test installation preflight failed.', 1;
END;

DECLARE @required_tests nvarchar(max) = N'[
    "[tests].[test.is_equal@fc_values]",
    "[tests].[test.is_json_equal@fc_json]",
    "[tests].[test.assert_equals@fc_assertions]",
    "[tests].[test.throw_error@fc_error_helpers]",
    "[tests].[test.assert_null@fc_null]",
    "[tests].[test.assert_not_null@fc_not_null]",
    "[tests].[test.fail@fc_failure]",
    "[tests].[test.fail_no_error@fc_no_error]",
    "[tests].[test.assert_error@fc_patterns]",
    "[tests].[test.assert_error@fc_error_assertions]",
    "[tests].[test.format_message@fc_parameters]",
    "[tests].[test.log@fc_logging]",
    "[tests].[test.throw@fc_throwing]",
    "[tests].[test.test@fc_catalog]",
    "[tests].[test.set_registration_scope@fc_context]",
    "[tests].[test.vector@fc_literals]"
]',
    @required_vectors nvarchar(max) = N'[
    {
        "procedure_name": "[tests].[power@vectors]",
        "parameters": "2,3,8"
    },
    {
        "procedure_name": "[tests].[power@vectors]",
        "parameters": "3,2,9"
    },
    {
        "procedure_name": "[tests].[power@vectors]",
        "parameters": "5,0,1"
    },
    {
        "procedure_name": "[tests].[power@vectors]",
        "parameters": "-2,3,-8"
    },
    {
        "procedure_name": "[tests].[test.vector@fc_literals]",
        "parameters": "0"
    },
    {
        "procedure_name": "[tests].[test.vector@fc_literals]",
        "parameters": "1,-9223372036854775808,-1234.5678,-1.25e-4,1,N''O''''Brien, Jr.'',''20240229'',''2024-02-29T01:02:03.123456'',0x00FF"
    },
    {
        "procedure_name": "[tests].[test.vector@fc_literals]",
        "parameters": "@bytes=0x,@text=N''\u017d\u4e2d, O''''Brien\\path'',@case_id=2,@flag=0,@approx=1.25e+3,@amount=0.0001,@number=9223372036854775807,@stamp=''2026-12-31T23:59:59.999999'',@day=''20261231''"
    },
    {
        "procedure_name": "[tests].[test.vector@fc_literals]",
        "parameters": "3,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL"
    },
    {
        "procedure_name": "[tests].[test.vector@fc_literals]",
        "parameters": "4,0,0.0000,0e0,0,N'''',NULL,NULL,0x"
    },
    {
        "procedure_name": "[tests].[test.vector@fc_literals]",
        "parameters": "@case_id=0,@number=DEFAULT,@amount=DEFAULT,@approx=DEFAULT,@flag=DEFAULT,@text=DEFAULT,@day=DEFAULT,@stamp=DEFAULT,@bytes=DEFAULT"
    }
]',
    @missing nvarchar(max), @message nvarchar(2048);
SELECT @missing = STRING_AGG(CONVERT(nvarchar(max), value), N', ')
FROM OPENJSON(@required_tests)
WHERE OBJECT_ID(value, N'P') IS NULL;
IF @missing IS NOT NULL
BEGIN
    DROP TABLE #fc_run;
    SET @message = N'Framework test installation incomplete. Missing procedures: ' + @missing;
    THROW 51090, @message, 1;
END;

DECLARE @engine_edition int = CAST(SERVERPROPERTY('EngineEdition') AS int),
    @previous_scope sql_variant, @vector_index int = 0,
    @procedure_name nvarchar(512), @parameters nvarchar(max);
IF @engine_edition <> 11
    EXEC sys.sp_executesql N'SELECT @scope = SESSION_CONTEXT(N''ttest:vectors:scope'');',
        N'@scope sql_variant OUTPUT', @scope = @previous_scope OUTPUT;
BEGIN TRY
    EXEC test.set_registration_scope N'global';
    WHILE @vector_index < (SELECT COUNT(*) FROM OPENJSON(@required_vectors))
    BEGIN
        SELECT @procedure_name = procedure_name, @parameters = parameters
        FROM OPENJSON(@required_vectors, CONCAT('$[', @vector_index, ']'))
        WITH (procedure_name nvarchar(512), parameters nvarchar(max));
        IF NOT EXISTS (
            SELECT 1 FROM [test].[test_vectors]
            WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2
                = @procedure_name COLLATE Latin1_General_100_BIN2
                AND CONVERT(nvarchar(max), parameters) COLLATE Latin1_General_100_BIN2
                = @parameters COLLATE Latin1_General_100_BIN2)
            EXEC test.vector @procedure_name, @parameters;
        SET @vector_index += 1;
    END;
    IF @engine_edition <> 11
        EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
END TRY
BEGIN CATCH
    IF @engine_edition <> 11
        EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
    DROP TABLE #fc_run;
    THROW;
END CATCH;
DROP TABLE #fc_run;
PRINT N'Framework tests and standard vectors installed. Execute run-framework-coverage-tests.sql.';
GO
