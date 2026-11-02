-- Run this entire file, including every GO batch, in ONE test-Warehouse session.
-- install.sql must already have completed successfully.
-- Adds 14 framework tests and runs them with the 14 basic tests.
-- Expected runner errors appear in Messages. The LAST result grid is authoritative.
-- Positive @fc_* tests remain installed; failing @fc_fixture_* probes are cleaned up.
-- Functional scenarios, not instrumented 100% line/branch coverage.
-- Add positive procedures to @positive below; its expected procedure count is automatic.
SET NOCOUNT ON;
-- A failed preflight must also block registration/cleanup in later GO batches.
DROP TABLE IF EXISTS #fc_run;
DROP TABLE IF EXISTS #fc_owned;
CREATE TABLE #fc_run (ready bit);
CREATE TABLE #fc_owned (name nvarchar(512));
INSERT #fc_run VALUES (0);
IF @@TRANCOUNT > 0
	THROW 51090, 'Run the coverage script outside a transaction.', 1;
IF OBJECT_ID(N'test.run', N'P') IS NULL OR OBJECT_ID(N'test.is_equal', N'FN') IS NULL
	OR OBJECT_ID(N'test.fail_no_error', N'FN') IS NULL
	OR OBJECT_ID(N'test.assert_error', N'FN') IS NULL
	THROW 51090, 'Install the framework before running coverage tests.', 1;
DECLARE @collision nvarchar(512);
SELECT TOP (1) @collision = name
FROM (VALUES
	(N'[test].[fc_observer]'), (N'[test].[fc_fixture]'),
	(N'[tests].[test.run@fc_fixture_a]'), (N'[tests].[test.run@fc_fixture_b]'),
	(N'[tests].[tests.test.throw@fc_fixture_other_schema]'),
	(N'[tests].[private.test.run@fc_fixture_private]'),
	(N'[tests].[test.run@fc_fixture_f1]'), (N'[tests].[test.run@fc_fixture_f2]'),
	(N'[tests].[test.run@fc_fixture_f3]'), (N'[tests].[test.run@fc_fixture_error]'),
	(N'[tests].[test.run@fc_fixture_rollback]'), (N'[tests].[test.run@fc_fixture_return]'),
	(N'[tests].[test.run@fc_fixture_open]'), (N'[tests].[test.run@fc_fixture_info]'),
	(N'[tests].[test.run@fc_fixture_number]'), (N'[tests].[test.run@fc_fixture_pattern]'),
	(N'[tests].[test.run@fc_fixture_long_fail]'),
	(N'[tests].[test.run@fc_fixture_marker_short]'), (N'[tests].[test.run@fc_fixture_marker_long]'),
	(N'[tests].[test.run@fc_fixture_created]'),
	(CONCAT(N'[tests].', QUOTENAME(N'test.run@fc_fixture_'
		+ REPLICATE(N'x', 128 - LEN(N'test.run@fc_fixture_')))))
) fixtures(name)
WHERE OBJECT_ID(name) IS NOT NULL;
IF @collision IS NOT NULL
BEGIN
	DECLARE @collision_message nvarchar(2048) = N'Coverage fixture already exists; nothing will overwrite/drop it: ' + @collision;
	THROW 51090, @collision_message, 1;
END;
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

-- Act / Assert: shortcuts must not evaluate JSON parsing.
SET @actual = test.is_equal(NULL, N'''');
IF @actual IS DISTINCT FROM 0 THROW 51091, ''Literal NULL/string comparison evaluated JSON parsing.'', 1;
SET @actual = test.is_equal(N''{bad JSON'', N''{bad JSON'');
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
SET @right = JSON_OBJECT(''id'': 1, ''text'': @text + N''y'');
SET @equal = test.is_json_equal(@left, @right);
IF @equal IS DISTINCT FROM 0 THROW 51091, ''Long JSON values were truncated.'', 1;

-- Arrange
SET @unicode = NCHAR(0x0416) + NCHAR(0x4E2D)
	+ CONVERT(nvarchar(2), 0x3DD800DE);
SET @left = JSON_ARRAY(@unicode);
SET @right = N''["\u0416\u4e2d\ud83d\ude00"]'';
SET @equal = test.is_json_equal(@left, @right);
IF @equal IS DISTINCT FROM 1 THROW 51091, ''Raw and escaped Unicode differ.'', 1;
SET @left = JSON_ARRAY(NCHAR(8) + NCHAR(12) + NCHAR(10)
	+ NCHAR(13) + NCHAR(9) + N''/\"'');
SET @right = N''["\b\f\n\r\t\/\\\""]'';
SET @equal = test.is_json_equal(@left, @right);
IF @equal IS DISTINCT FROM 1 THROW 51091, ''JSON escape decoding differs.'', 1;');
	DROP PROCEDURE IF EXISTS [tests].[test.is_equal_openjson@fc_json];
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_equals@fc_assertions]
AS
PRINT N''Check equality/NULL assertions and 3 failure cases.'';
PRINT N''Expect: valid checks pass; all 3 failures are caught.'';

DECLARE @result nvarchar(max), @caught bit, @i int, @message nvarchar(max);

-- Arrange
SET @i = 0;

-- Act / Assert: successful assertions return the empty string.
SET @result = test.assert_equals(N''equal'', N''1.0'', N''1'');
IF @result IS DISTINCT FROM N'''' THROW 51091, ''assert_equals success result changed.'', 1;
SET @result = test.assert_null(N''null'', NULL);
IF @result IS DISTINCT FROM N'''' THROW 51091, ''assert_null success result changed.'', 1;
SET @result = test.assert_not_null(N''not null'', 0x);
IF @result IS DISTINCT FROM N'''' THROW 51091, ''Empty binary was treated as NULL.'', 1;
WHILE @i < 3
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 SET @result = test.assert_equals(N''fc assertion marker'', N''a'', N''b'');
		ELSE IF @i = 1 SET @result = test.assert_null(N''fc assertion marker'', 0x01);
		ELSE SET @result = test.assert_not_null(N''fc assertion marker'', NULL);
	END TRY
	BEGIN CATCH
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Unit-test fail:'', @message) > 0
			AND CHARINDEX(N''fc assertion marker'', @message) > 0 SET @caught = 1;
	END CATCH;

	-- Assert
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
	SET @caught = 0;
	BEGIN TRY
		IF @i = 0 SET @result = test.throw_error(N''fc raw error'');
		ELSE IF @i = 1 SET @result = test.fail(N''fc explicit fail'');
		ELSE SET @result = test.fail_no_error();
	END TRY
	BEGIN CATCH
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 245 AND (
			(@i = 0 AND CHARINDEX(N''fc raw error'', @message) > 0) OR
			(@i = 1 AND CHARINDEX(N''Unit-test fail: fc explicit fail'', @message) > 0) OR
			(@i = 2 AND CHARINDEX(N''<<No error>>'', @message) > 0)) SET @caught = 1;
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
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Error: '', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	-- Assert
	IF @caught = 0 THROW 51091, ''A numeric or empty raw error message did not throw.'', 1;
	SET @i += 1;
END;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_null@fc_null]
AS
PRINT N''Check that assert_null accepts only NULL.'';
PRINT N''Expect: NULL passes; the non-NULL failure is caught.'';

DECLARE @result nvarchar(max), @caught bit;

-- Arrange
SET @caught = 0;

-- Act
SET @result = test.assert_null(N''NULL is NULL'', NULL);

-- Assert
IF @result IS DISTINCT FROM N'''' THROW 51091, ''assert_null rejected NULL.'', 1;

-- Act
BEGIN TRY
	SET @result = test.assert_null(N''fc empty binary is not NULL'', 0x);
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc empty binary is not NULL'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

-- Assert
IF @caught = 0 THROW 51091, ''assert_null accepted an empty non-NULL value.'', 1;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_not_null@fc_not_null]
AS
PRINT N''Check that assert_not_null rejects only NULL.'';
PRINT N''Expect: zero bytes pass; the NULL failure is caught.'';

DECLARE @result nvarchar(max), @caught bit;

-- Arrange
SET @caught = 0;

-- Act
SET @result = test.assert_not_null(N''zero bytes are not NULL'', 0x0000);
IF @result IS DISTINCT FROM N'''' THROW 51091, ''assert_not_null rejected zero bytes.'', 1;

-- Act
BEGIN TRY
	SET @result = test.assert_not_null(N''fc NULL must fail'', NULL);
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc NULL must fail'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

-- Assert
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
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Unit-test fail: 123'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

-- Assert
IF @caught = 0 THROW 51091, ''fail did not reject a numeric-only message.'', 1;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	SET @result = test.fail(NULL);
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Unit-test fail:'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

-- Assert
IF @caught = 0 THROW 51091, ''fail(NULL) did not raise a failure.'', 1;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	EXEC(N'CREATE OR ALTER PROC [tests].[test.fail_no_error@fc_no_error]
AS
PRINT N''Call fail_no_error() after an expected error is missing.'';
PRINT N''Expect: its no-error marker is raised and caught.'';

DECLARE @result nvarchar(max), @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''<<No error>>'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

-- Assert
IF @caught = 0 THROW 51091, ''fail_no_error() did not raise its no-error marker.'', 1;');
	DROP PROCEDURE IF EXISTS [tests].[test.error@fc_no_error];
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_error@fc_patterns]
AS
PRINT N''Check error LIKE patterns and the no-error marker.'';
PRINT N''Expect: matching passes; the invalid match is caught.'';

DECLARE @result int, @marker nvarchar(max), @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	THROW 51011, ''fc wildcard_value'', 1;
END TRY
BEGIN CATCH
	SET @result = test.assert_error(N''literal underscore and wildcard'', DEFAULT, N''fc wildcard[_]%'', DEFAULT);
	IF @result IS NOT NULL THROW 51091, ''A matching LIKE pattern returned a value.'', 1;
END CATCH;
BEGIN TRY
	SET @marker = test.fail_no_error();
END TRY
BEGIN CATCH
	BEGIN TRY
		SET @result = test.assert_error(N''fc no-error marker must be rejected'', DEFAULT, N''%<<No error>>%'', DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc no-error marker must be rejected'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
END CATCH;

-- Assert
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

DECLARE @result int, @caught bit, @value int, @i int;

-- Arrange
SET @caught = 0;

-- Act: a real conversion error must still be accepted.
BEGIN TRY
	SET @value = CONVERT(int, N''fc genuine conversion error'');
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() <> 245 THROW;
	SET @result = test.assert_error(N''genuine conversion error'', 245, DEFAULT, DEFAULT);
	SET @caught = 1;
END CATCH;

-- Assert.
IF @caught = 0 OR @result IS NOT NULL
	THROW 51091, ''A genuine conversion error was not accepted.'', 1;
SET @caught = 0;
BEGIN TRY
	THROW 51011, ''fc expected exception'', 1;
END TRY
BEGIN CATCH
	SET @result = test.assert_error(N''matching number'', 51011, DEFAULT, DEFAULT);
	IF @result IS NOT NULL THROW 51091, ''Matching error number returned a value.'', 1;
	SET @result = test.assert_error(N''matching pattern'', DEFAULT, N''%fc expected exception%'', DEFAULT);
	IF @result IS NOT NULL THROW 51091, ''Matching error pattern returned a value.'', 1;
	BEGIN TRY
		SET @result = test.assert_error(N''fc wrong number'', 51012, DEFAULT, DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc wrong number'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
	IF @caught = 0 THROW 51091, ''Wrong error number was accepted.'', 1;
	SET @caught = 0;
	BEGIN TRY
		SET @result = test.assert_error(N''fc wrong pattern'', DEFAULT, N''%not the actual message%'', DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc wrong pattern'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
	IF @caught = 0 THROW 51091, ''Wrong error pattern was accepted.'', 1;
END CATCH;
-- Act: the no-error sentinel must NOT satisfy expected error 245.
SET @caught = 0;
BEGIN TRY
	SET @value = test.fail_no_error();
END TRY
BEGIN CATCH
	BEGIN TRY
		SET @result = test.assert_error(N''fc sentinel is not a real conversion error'', 245, DEFAULT, DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(
			N''Unit-test fail: fc sentinel is not a real conversion error'', ERROR_MESSAGE()) > 0
			SET @caught = 1;
	END CATCH;
END CATCH;

-- Assert.
IF @caught = 0 THROW 51091, ''Error number assertion accepted the no-error sentinel.'', 1;
-- Arrange
SET @i = 0;
WHILE @i < 2
BEGIN
	SET @caught = 0;
	BEGIN TRY
		IF @i = 0 SET @result = test.assert_error(N''fc no active error'', 51011, DEFAULT, DEFAULT);
		ELSE SET @result = test.assert_error(N''fc no active error'', DEFAULT, N''%anything%'', DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc no active error'', ERROR_MESSAGE()) > 0 SET @caught = 1;
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

-- Act / Assert: each parameter arrangement has its own exact reference.
SET @actual = test.format_message(N''%1|%2|%3|%4'', @date_text, CONVERT(nvarchar(4000), 0x010203, 1), 42, NULL);
IF @actual IS DISTINCT FROM N''2026-03-04T05:06:07.123456|0x010203|42|<null>''
	THROW 51091, ''Explicit ISO/hex/numeric/NULL substitution failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', NULL, 42, @hex, @date_text);
IF @actual IS DISTINCT FROM N''<null>|42|0xAB|2026-03-04T05:06:07.123456''
	THROW 51091, ''Formatting in alternate parameter positions failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', 42, @date_text, NULL, @hex);
IF @actual IS DISTINCT FROM N''42|2026-03-04T05:06:07.123456|<null>|0xAB''
	THROW 51091, ''Second date/fourth binary parameter formatting failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', @hex, NULL, @date_text, 42);
IF @actual IS DISTINCT FROM N''0xAB|<null>|2026-03-04T05:06:07.123456|42''
	THROW 51091, ''Third date/first binary parameter formatting failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', DEFAULT, DEFAULT, DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''%1|%2|%3|%4'' THROW 51091, ''Unassigned placeholders changed.'', 1;
SET @actual = test.format_message(N''%1|%2'', N''10/31/26'', N''0xabcdef'', DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''10/31/26|0xabcdef'' THROW 51091, ''Text was reclassified as date/binary.'', 1;
SET @date = CAST(''2026-03-04T00:00:00'' AS datetime2(6));
SET @actual = test.format_message(N''%1'', CONVERT(nvarchar(33), @date, 126), DEFAULT, DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''2026-03-04T00:00:00'' THROW 51091, ''ISO midnight text changed.'', 1;
SET @actual = test.format_message(N''%1|%2'', CONVERT(nvarchar(4000), 0x, 1),
	CONVERT(nvarchar(33), CAST(NULL AS datetime2(6)), 126), DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''0x|<null>'' THROW 51091, ''Empty hex or NULL ISO substitution failed.'', 1;
-- Arrange
SET @raw_date = @date;
SET @raw_binary = 0x41004200;
SET @plain = CONCAT(CAST(@raw_date AS nvarchar(4000)), N''|'', CAST(@raw_binary AS nvarchar(4000)));
SET @actual = test.format_message(N''%1|%2'', @raw_date, @raw_binary, DEFAULT, DEFAULT);
IF CONVERT(varbinary(max), @actual) IS DISTINCT FROM CONVERT(varbinary(max), @plain)
	THROW 51091, ''Formatter still applies implicit date/binary formatting.'', 1;
SET @actual = test.format_message(NULL, 1, 2, 3, 4);
IF @actual IS NOT NULL THROW 51091, ''NULL message changed.'', 1;
SET @actual = test.format_message(N''%1:%1:100%'', NCHAR(381), DEFAULT, DEFAULT, DEFAULT);
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
-- Act / Assert: each call must complete without throwing.
EXEC test.log @message = NULL, @data = NULL;
EXEC test.log @message = N''fc logger %1 %2 %3 %4 100%'', @p1 = 42, @p2 = NULL,
	@p3 = @hex, @p4_str = N''wide text'', @rowcount = 0, @proc_id = @id, @severity = N''warning'';
EXEC test.log @message = N''fc inline data'', @data = N''short 100% data'', @severity = N''info'';
EXEC test.log @message = N''fc multiline data'', @data = @multiline;
EXEC test.log @message = N''fc chunked data (4100 characters)'', @data = @data;
-- Act / Assert: a literal percent at a truncation boundary must not become a format token.
EXEC test.log @message = @boundary;
EXEC test.log @message = N''fc boundary data'', @data = @boundary;');
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	EXEC(N'CREATE OR ALTER PROC [tests].[test.throw@fc_throwing]
AS
PRINT N''Throw 3 exceptions: no ID, valid ID, invalid ID.'';
PRINT N''Expect: all 3 caught; message and procedure ID verified.'';

DECLARE @id int, @caught bit, @i int, @message nvarchar(max), @scenario nvarchar(128);

-- Arrange
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
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 70000 AND CHARINDEX(N''fc thrown exception'', @message) = 1
			AND ((@i = 0 AND @message = N''fc thrown exception'')
				OR (@i = 1 AND CHARINDEX(N''[tests].[test.throw@fc_throwing]'', @message) > 0)
				OR (@i = 2 AND CHARINDEX(N''<Procedure:> -1'', @message) > 0)) SET @caught = 1;
	END CATCH;

	-- Assert
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
	@schema nvarchar(128), @object nvarchar(128), @action nvarchar(128), @main nvarchar(128);

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

-- Act / Assert: discovery must preserve both conceptual actions.
IF (SELECT COUNT(*) FROM test.test
	WHERE test_proc_name IN (N''fc_catalog_concept@fc_catalog_probe'', N''fc_catalog_concept@fc_catalog_probe.with.dot'')
		AND tested_object_schema_name IS NULL AND tested_object_full_name IS NULL
		AND tested_object_main_schema_name IS NULL AND tested_object_name = N''fc_catalog_concept''
		AND tested_action = STUFF(test_proc_name, 1, CHARINDEX(''@'', test_proc_name), N'''')) <> 2
	THROW 51091, ''Conceptual discovery must preserve the object/action without assigning a schema.'', 1;
EXEC [tests].[test.test@name_convention];
EXEC(N''CREATE PROC [tests].[private.test.run@fc_catalog_probe] AS RETURN 0;'');
EXEC(N''CREATE PROC [tests].[test.log@fc_catalog_probe]]edge@extra] AS RETURN 0;'');

-- Act.
SELECT @schema = tested_object_schema_name, @object = tested_object_name,
	@action = tested_action, @main = tested_object_main_schema_name
FROM test.test WHERE test_proc_full_name = N''[tests].[test.run@fc_catalog_probe]'';

-- Assert.
IF @schema IS DISTINCT FROM N''test'' OR @object IS DISTINCT FROM N''run''
	OR @action IS DISTINCT FROM N''fc_catalog_probe'' OR @main IS DISTINCT FROM N''test''
	THROW 51091, ''Regular discovery/name parsing failed.'', 1;
SELECT @schema = tested_object_schema_name, @object = tested_object_name, @main = tested_object_main_schema_name
FROM test.test WHERE test_proc_full_name = N''[tests].[private.test.run@fc_catalog_probe]'';
IF @schema IS DISTINCT FROM N''private'' OR @object IS DISTINCT FROM N''test.run'' OR @main IS DISTINCT FROM N''test''
	THROW 51091, ''Private-schema main-schema parsing failed.'', 1;
SET @action = NULL;
SELECT @action = tested_action FROM test.test
WHERE test_proc_full_name = N''[tests].[test.log@fc_catalog_probe]]edge@extra]'';
IF @action IS DISTINCT FROM N''fc_catalog_probe]edge@extra''
	THROW 51091, ''Bracket escaping or multiple action separators failed.'', 1;
ROLLBACK;

-- UDF assertion errors can doom an explicit transaction, so run invalid-name probes outside it.
-- Arrange.
EXEC(N''CREATE PROC [tests].[fc_catalog_invalid] AS RETURN 0;'');
SET @invalid_one = 1;
EXEC(N''CREATE PROC [tests].[fc_catalog_invalid@] AS RETURN 0;'');
SET @invalid_two = 1;
EXEC(N''CREATE PROC [tests].[@fc_catalog_invalid] AS RETURN 0;'');
SET @invalid_three = 1;

-- Act.
BEGIN TRY
	EXEC [tests].[test.test@name_convention];
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() <> 245 THROW;
	SET @naming_error = ERROR_MESSAGE();
END CATCH;

-- Assert.
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
BEGIN
EXEC(N'CREATE PROC test.fc_observer
	@message nvarchar(max) = NULL, @data nvarchar(max) = NULL,
	@severity nvarchar(8) = N''debug'', @p1_str nvarchar(max) = NULL, @p2_str nvarchar(max) = NULL,
	@proc_id int = NULL, @rowcount int = NULL
AS
SET NOCOUNT ON;
INSERT #fc_audit(kind, name, message, severity, proc_id, row_count)
VALUES (''log'', CONVERT(varchar(512), @p1_str), CONVERT(varchar(8000), COALESCE(@p2_str, @message)),
	CONVERT(varchar(8), @severity), @proc_id, @rowcount);
DECLARE @mode varchar(16);
SELECT @mode = logger_failure FROM #fc_control;
IF (@mode = ''before'' AND @data IS NOT NULL) OR (@mode = ''error'' AND @severity = N''error'')
	OR (@mode = ''summary'' AND @severity = N''Info'')
	THROW 51017, ''fc intentional logger failure'', 1;');
INSERT #fc_owned VALUES (N'[test].[fc_observer]');
END;
GO
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
EXEC(N'CREATE PROC test.fc_fixture @name nvarchar(512), @mode varchar(24)
AS
SET NOCOUNT ON;
DECLARE @require_before bit, @before int, @executed int, @result int;
SELECT @require_before = require_before FROM #fc_control;
SELECT @before = COUNT(*) FROM #fc_audit WHERE kind = ''before'';
SELECT @executed = COUNT(*) FROM #fc_audit WHERE kind = ''exec'';
IF @require_before = 1 AND @before <> @executed + 1
	THROW 51018, ''Callback did not precede each test execution.'', 1;
INSERT #fc_audit(kind, name) VALUES (''exec'', CONVERT(varchar(512), @name));
IF @mode = ''fail'' SET @result = test.fail(N''fc intentional assertion failure'');
IF @mode = ''long_fail''
BEGIN
	DECLARE @long_message nvarchar(max) = REPLICATE(CAST(N''x'' AS nvarchar(max)), 3000);
	SET @result = test.fail(@long_message);
END;
IF @mode = ''number'' OR @mode = ''pattern''
BEGIN
	BEGIN TRY
		THROW 51011, ''fc original exception'', 1;
	END TRY
	BEGIN CATCH
		IF @mode = ''number'' SET @result = test.assert_error(N''fc number mismatch'', 51012, DEFAULT, DEFAULT);
		ELSE SET @result = test.assert_error(N''fc pattern mismatch'', DEFAULT, N''%does not match%'', DEFAULT);
	END CATCH;
END;
IF @mode = ''marker_short'' THROW 51011, ''Unit-test fail: x'', 1;
IF @mode = ''marker_long'' THROW 51011, ''fc ordinary exception containing Unit-test fail: must stay unchanged'', 1;
IF @mode = ''error''
BEGIN
	BEGIN TRAN;
	INSERT #fc_probe VALUES (1);
	THROW 51011, ''fc intentional unexpected error'', 1;
END;
IF @mode = ''rollback''
BEGIN
	BEGIN TRAN;
	INSERT #fc_probe VALUES (1);
	ROLLBACK;
END;
IF @mode = ''open_transaction''
BEGIN
	BEGIN TRAN;
	INSERT #fc_probe VALUES (1);
END;
IF @mode = ''info'' RAISERROR(''fc intentional informational message'', 0, 1);
IF @mode = ''return'' RETURN 7;');
INSERT #fc_owned VALUES (N'[test].[fc_fixture]');
END;
GO
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
	THROW 51090, 'Coverage fixture preflight failed. Registration was skipped.', 1;
IF @@TRANCOUNT > 0 THROW 51090, 'Coverage registration left an active transaction.', 1;
DROP TABLE IF EXISTS #fc_audit;
DROP TABLE IF EXISTS #fc_control;
DROP TABLE IF EXISTS #fc_probe;
DROP TABLE IF EXISTS #fc_report;
CREATE TABLE #fc_audit (
	kind varchar(16), name varchar(512), message varchar(8000),
	severity varchar(8), proc_id int, row_count int
);
CREATE TABLE #fc_control (require_before bit, logger_failure varchar(16));
CREATE TABLE #fc_probe (value int);
CREATE TABLE #fc_report (scenario varchar(100), status varchar(16), detail varchar(8000));
INSERT #fc_control VALUES (0, NULL);

DECLARE @positive nvarchar(max) =
	N'[tests].[test.throw]|[tests].[test.format_message]|[tests].[test.test]|[tests].[test.test@name_convention]|'
	+ N'[tests].[test.assert_equals]|[tests].[test.assert_not_null]|[tests].[test.assert_null]|'
	+ N'[tests].[test.is_equal]|[tests].[sys.objects@tables]|[tests].[stdev@basic]|'
	+ N'[tests].[data_types@basic]|'
	+ N'[tests].[test.assert_float_equals]|'
	+ N'[tests].[test.assert_resultset_equals]|'
	+ N'[tests].[test.assert_error]|'
	+ N'[tests].[test.is_equal@fc_values]|[tests].[test.is_json_equal@fc_json]|'
	+ N'[tests].[test.assert_equals@fc_assertions]|[tests].[test.throw_error@fc_error_helpers]|'
	+ N'[tests].[test.assert_null@fc_null]|[tests].[test.assert_not_null@fc_not_null]|'
	+ N'[tests].[test.fail@fc_failure]|[tests].[test.fail_no_error@fc_no_error]|[tests].[test.assert_error@fc_patterns]|'
	+ N'[tests].[test.assert_error@fc_error_assertions]|[tests].[test.format_message@fc_parameters]|'
	+ N'[tests].[test.log@fc_logging]|[tests].[test.throw@fc_throwing]|[tests].[test.test@fc_catalog]',
	@code int = 0, @error nvarchar(max) = NULL, @summary nvarchar(max), @run_id int = OBJECT_ID(N'test.run');
DECLARE @positive_count int = (SELECT COUNT(*) FROM STRING_SPLIT(@positive, N'|'));
BEGIN TRY
	EXEC test.run @test_names = @positive, @log_proc_name = N'test.fc_observer';
END TRY
BEGIN CATCH
	SET @code = ERROR_NUMBER();
	SET @error = ERROR_MESSAGE();
	IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH;
SELECT @summary = message FROM #fc_audit WHERE kind = 'log' AND severity = 'Info';
INSERT #fc_report VALUES ('positive unit tests and bundled tests',
	IIF(@code = 0 AND @summary LIKE CONCAT(@positive_count, ' tests of % executed. Succeded: ',
		@positive_count, ', failed: 0, errors: 0'), 'PASS', 'FAIL'),
	CONVERT(varchar(8000), COALESCE(@error, @summary, N'No successful runner summary')));

DECLARE @map nvarchar(max) = N'[
 {"key":"a","name":"[tests].[test.run@fc_fixture_a]","mode":"success"},
 {"key":"b","name":"[tests].[test.run@fc_fixture_b]","mode":"success"},
 {"key":"c","name":"[tests].[tests.test.throw@fc_fixture_other_schema]","mode":"success"},
 {"key":"private","name":"[tests].[private.test.run@fc_fixture_private]","mode":"success"},
 {"key":"f1","name":"[tests].[test.run@fc_fixture_f1]","mode":"fail"},
 {"key":"f2","name":"[tests].[test.run@fc_fixture_f2]","mode":"fail"},
 {"key":"f3","name":"[tests].[test.run@fc_fixture_f3]","mode":"fail"},
 {"key":"error","name":"[tests].[test.run@fc_fixture_error]","mode":"error"},
 {"key":"rollback","name":"[tests].[test.run@fc_fixture_rollback]","mode":"rollback"},
 {"key":"return","name":"[tests].[test.run@fc_fixture_return]","mode":"return"},
 {"key":"open","name":"[tests].[test.run@fc_fixture_open]","mode":"open_transaction"},
 {"key":"info","name":"[tests].[test.run@fc_fixture_info]","mode":"info"},
 {"key":"number","name":"[tests].[test.run@fc_fixture_number]","mode":"number"},
 {"key":"pattern","name":"[tests].[test.run@fc_fixture_pattern]","mode":"pattern"},
 {"key":"long_fail","name":"[tests].[test.run@fc_fixture_long_fail]","mode":"long_fail"},
 {"key":"marker_short","name":"[tests].[test.run@fc_fixture_marker_short]","mode":"marker_short"},
 {"key":"marker_long","name":"[tests].[test.run@fc_fixture_marker_long]","mode":"marker_long"},
 {"key":"unknown","name":"[tests].[test.run@fc_fixture_missing]","mode":null}
]';
DECLARE @long_name nvarchar(128) = N'test.run@fc_fixture_' + REPLICATE(N'x', 128 - LEN(N'test.run@fc_fixture_'));
SET @map = JSON_MODIFY(@map, 'append $', JSON_QUERY(JSON_OBJECT(
	'key': 'long', 'name': CONCAT(N'[tests].', QUOTENAME(@long_name)), 'mode': 'success')));
DECLARE @i int = 0, @n int = (SELECT COUNT(*) FROM OPENJSON(@map)),
	@name nvarchar(512), @mode varchar(24), @sql nvarchar(max);
WHILE @i < @n
BEGIN
	SELECT @name = name, @mode = mode FROM OPENJSON(@map, CONCAT('$[', @i, ']'))
	WITH (name nvarchar(512), mode varchar(24));
	IF @mode IS NOT NULL
	BEGIN
		SET @sql = N'CREATE PROC ' + @name
			+ N' AS DECLARE @r int; EXEC @r = test.fc_fixture @name = N'''
			+ REPLACE(@name, N'''', N'''''') + N''', @mode = ''' + @mode + N'''; RETURN @r;';
		EXEC sys.sp_executesql @sql;
		INSERT #fc_owned VALUES (@name);
	END;
	SET @i += 1;
END;

DECLARE @cases nvarchar(max) = N'[
 {"id":"explicit names and schema grouping","names":"a|b|c","exec":3},
 {"id":"default discovery with explicit exclusion","names":"a","discover":1,"exec":1},
 {"id":"default logger smoke","names":"a","default_logger":1,"exec":1,"summary":0},
 {"id":"trimmed test names","names":"a|b","trim_names":1,"exec":2},
 {"id":"exclude a test name","names":"a|b","exclude":"b","expected":"a","exec":1},
 {"id":"exclude multiple test names","names":"a|b|c","exclude":"a|c","expected":"b","exec":1},
 {"id":"include schema","names":"a|c","schemas":"test","expected":"a","exec":1},
 {"id":"include multiple trimmed schemas","names":"a|c","schemas":" test , tests ","exec":2},
 {"id":"exclude schema","names":"a|c","exclude_schemas":" tests ","expected":"a","exec":1},
 {"id":"include and exclude same schema","names":"a|b","schemas":"test","exclude_schemas":"test","exec":0},
 {"id":"private main-schema filter","names":"private","schemas":"test","exec":1},
 {"id":"empty name list validation","names":"","exec":0,"code":50000,"summary":0},
 {"id":"long procedure identifier","names":"long","exec":1},
 {"id":"callback ordering and context","names":"a|b","callback":1,"exec":2},
 {"id":"callback creation does not change selected snapshot","names":"a","discover":1,"callback":1,"callback_create":1,"exec":1},
 {"id":"assertion failure classification","names":"f1","exec":1,"success":0,"fail":1,"code":70000},
 {"id":"error-number assertion is a failure","names":"number","exec":1,"success":0,"fail":1,"code":70000},
 {"id":"error-pattern assertion is a failure","names":"pattern","exec":1,"success":0,"fail":1,"code":70000},
 {"id":"truncated assertion diagnostic is a failure","names":"long_fail","exec":1,"success":0,"fail":1,"code":70000},
 {"id":"short marker in ordinary exception","names":"marker_short","exec":1,"success":0,"errors":1,"code":70000,"message":"Unit-test fail: x"},
 {"id":"long marker in ordinary exception","names":"marker_long","exec":1,"success":0,"errors":1,"code":70000,"message":"fc ordinary exception containing Unit-test fail: must stay unchanged"},
 {"id":"unexpected error and rollback","names":"error","exec":1,"success":0,"errors":1,"code":70000},
 {"id":"mixed result classification","names":"a|f1|error","exec":3,"success":1,"fail":1,"errors":1,"code":70000},
 {"id":"failure limit one","names":"f1|f2|f3","limit":1,"exec":1,"success":0,"fail":1,"code":70000},
 {"id":"failure limit two","names":"f1|f2|f3","limit":2,"exec":2,"success":0,"fail":2,"code":70000},
 {"id":"zero failure limit preserves existing behavior","names":"f1|f2|f3","limit":0,"exec":3,"success":0,"fail":3,"code":70000},
 {"id":"negative failure limit preserves existing behavior","names":"f1|f2|f3","limit":-1,"exec":3,"success":0,"fail":3,"code":70000},
 {"id":"test-owned rollback","names":"rollback","exec":1},
 {"id":"unbalanced test transaction","names":"open","exec":1,"success":0,"errors":1,"code":70000},
 {"id":"nonzero RETURN is not an error","names":"return","exec":1},
 {"id":"informational RAISERROR is not an error","names":"info","exec":1},
 {"id":"callback error interrupts before execution","names":"a","callback_error":1,"exec":0,"code":51016,"summary":0},
 {"id":"failed callback rolls back its transaction","names":"a","callback_error":1,"callback_transaction":1,"exec":0,"code":51016,"summary":0},
 {"id":"logger error before execution","names":"a","callback":1,"logger":"before","exec":0,"before":1,"code":51017,"summary":0},
 {"id":"logger error during failure reporting","names":"f1","logger":"error","exec":1,"code":51017,"summary":0},
 {"id":"logger error during summary reporting","names":"a","logger":"summary","exec":1,"code":51017},
 {"id":"duplicate with outer CATCH","names":"a|a|a","expected":"a|a","callback":1,"exec":2,"code":50000,"summary":0},
 {"id":"duplicate failing test with outer CATCH","names":"f1|f1|f1","expected":"f1|f1","callback":1,"exec":2,"code":50000,"summary":0},
 {"id":"duplicate error test with outer CATCH","names":"error|error|error","expected":"error|error","callback":1,"exec":2,"code":50000,"summary":0},
 {"id":"missing selection validates NULL name","names":"unknown","callback":1,"exec":0,"before":1,"code":50000,"summary":0}
]';
SET @i = 0;
SET @n = (SELECT COUNT(*) FROM OPENJSON(@cases));
DECLARE @id varchar(100), @keys nvarchar(max), @exclude_keys nvarchar(max),
	@expected_keys nvarchar(max), @expected_message nvarchar(max), @partial_selection bit,
	@names nvarchar(max), @exclude nvarchar(max), @schemas nvarchar(256), @exclude_schemas nvarchar(256),
	@limit int, @callback bit, @callback_error bit, @callback_transaction bit, @logger varchar(16),
	@discover bit, @trim_names bit, @default_logger bit, @callback_create bit, @logger_proc nvarchar(256),
	@expected_exec int, @expected_success int, @expected_fail int, @expected_errors int,
	@expected_code int, @expected_summary bit, @expected_before int,
	@before_callback nvarchar(max), @executed int, @before int, @leaked int, @ok bit,
	@expected_pattern nvarchar(max);
WHILE @i < @n
BEGIN
	-- Arrange: expected identities are independent of runner filtering.
	SELECT @id = id, @keys = names, @exclude_keys = exclude_names, @schemas = schemas,
		@expected_keys = COALESCE(expected_names, names), @expected_message = expected_message,
		@exclude_schemas = exclude_schemas, @limit = limit_failed, @callback = ISNULL(callback, 0),
		@callback_error = ISNULL(callback_error, 0), @callback_transaction = ISNULL(callback_transaction, 0), @logger = logger,
		@discover = ISNULL(discover, 0), @trim_names = ISNULL(trim_names, 0),
		@default_logger = ISNULL(default_logger, 0), @callback_create = ISNULL(callback_create, 0),
		@expected_exec = executions, @expected_success = ISNULL(success, executions),
		@expected_fail = ISNULL(failed, 0), @expected_errors = ISNULL(errors, 0),
		@expected_code = ISNULL(code, 0), @expected_summary = ISNULL(summary, 1),
		@expected_before = ISNULL(before_count, IIF(callback = 1, executions, 0))
	FROM OPENJSON(@cases, CONCAT('$[', @i, ']'))
	WITH (id varchar(100), names nvarchar(max), exclude_names nvarchar(max) '$.exclude',
		expected_names nvarchar(max) '$.expected', expected_message nvarchar(max) '$.message',
		schemas nvarchar(256), exclude_schemas nvarchar(256), limit_failed int '$.limit',
		callback bit, callback_error bit, callback_transaction bit, logger varchar(16), executions int '$.exec',
		discover bit, trim_names bit, default_logger bit, callback_create bit,
		success int, failed int '$.fail', errors int, code int, summary bit, before_count int '$.before');
	IF @expected_exec = 0 SET @expected_keys = N'';
	SET @partial_selection = IIF(@limit > 0 AND @expected_exec <
		(SELECT COUNT(*) FROM STRING_SPLIT(@expected_keys, N'|')), 1, 0);
	SELECT @names = ISNULL(STRING_AGG(CONVERT(nvarchar(max), m.name), N'|'), N'')
	FROM OPENJSON(@map) WITH ([key] nvarchar(32), name nvarchar(512)) m
	JOIN STRING_SPLIT(@keys, N'|') s ON s.value = m.[key];
	SET @exclude = NULL;
	IF @exclude_keys IS NOT NULL
		SELECT @exclude = STRING_AGG(CONVERT(nvarchar(max), m.name), N'|')
		FROM OPENJSON(@map) WITH ([key] nvarchar(32), name nvarchar(512)) m
		JOIN STRING_SPLIT(@exclude_keys, N'|') s ON s.value = m.[key];
	IF @trim_names = 1 SET @names = N' ' + REPLACE(@names, N'|', N' | ') + N' ';
	IF @discover = 1
	BEGIN
		SELECT @exclude = STRING_AGG(CONVERT(nvarchar(max), test_proc_full_name), N'|')
		FROM test.test WHERE test_proc_full_name <> N'[tests].[test.run@fc_fixture_a]';
		SET @names = NULL;
	END;
	TRUNCATE TABLE #fc_audit;
	TRUNCATE TABLE #fc_probe;
	UPDATE #fc_control SET require_before = @callback, logger_failure = @logger;
	SET @before_callback = IIF(@callback = 1, N'INSERT #fc_audit(kind) VALUES (''before'');', NULL);
	IF @callback_error = 1 SET @before_callback = N'THROW 51016, ''fc intentional callback error'', 1;';
	IF @callback_transaction = 1 SET @before_callback =
		N'BEGIN TRAN; INSERT #fc_probe VALUES (1); THROW 51016, ''fc intentional callback error'', 1;';
	IF @callback_create = 1 SET @before_callback =
		N'EXEC(N''CREATE PROC [tests].[test.run@fc_fixture_created] AS RETURN 0;''); '
		+ N'INSERT #fc_owned VALUES (N''[tests].[test.run@fc_fixture_created]''); '
		+ N'INSERT #fc_audit(kind) VALUES (''before'');';
	SET @logger_proc = IIF(@default_logger = 1, NULL, N'test.fc_observer');
	SET @code = 0;
	SET @error = NULL;
	SET @leaked = 0;

	-- Act.
	BEGIN TRY
		IF @discover = 1 AND EXISTS (SELECT 1 FROM test.test WHERE CHARINDEX(N'|', test_proc_full_name) > 0)
			THROW 51092, 'Cannot safely exclude existing pipe-named procedures from default discovery.', 1;
		EXEC test.run @test_names = @names, @exclude_test_names = @exclude,
			@schemas = @schemas, @exclude_schemas = @exclude_schemas, @limit_failed = @limit,
			@before_callback = @before_callback, @log_proc_name = @logger_proc;
		SET @leaked = @@TRANCOUNT;
		IF @@TRANCOUNT > 0 ROLLBACK;
	END TRY
	BEGIN CATCH
		SET @code = ERROR_NUMBER();
		SET @error = ERROR_MESSAGE();
		SET @leaked = @@TRANCOUNT;
		IF @@TRANCOUNT > 0 ROLLBACK;
	END CATCH;

	-- Assert: counts, identities/multiplicity, diagnostics and transaction cleanup.
	SELECT @executed = COUNT(*) FROM #fc_audit WHERE kind = 'exec';
	SELECT @before = COUNT(*) FROM #fc_audit WHERE kind = 'before';
	SET @summary = NULL;
	SELECT @summary = message FROM #fc_audit WHERE kind = 'log' AND severity = 'Info';
	SET @ok = IIF(@code = @expected_code AND @executed = @expected_exec
		AND @before = @expected_before AND @leaked = 0, 1, 0);
	;WITH expected_names AS (
		SELECT CONVERT(varchar(512), m.name) AS name, COUNT(*) AS executions
		FROM OPENJSON(@map) WITH ([key] nvarchar(32), name nvarchar(512)) m
		JOIN STRING_SPLIT(@expected_keys, N'|') s ON s.value = m.[key]
		GROUP BY m.name
	), actual_names AS (
		SELECT name, COUNT(*) AS executions FROM #fc_audit WHERE kind = 'exec' GROUP BY name
	)
	SELECT @ok = IIF(EXISTS (
		SELECT 1 FROM expected_names e FULL JOIN actual_names a ON a.name = e.name
		WHERE e.name IS NULL OR ISNULL(a.executions, 0) > e.executions
			OR (@partial_selection = 0 AND a.executions IS DISTINCT FROM e.executions)
	), 0, @ok);
	IF @expected_message IS NOT NULL AND CHARINDEX(@expected_message, COALESCE(@error, N'')) = 0 SET @ok = 0;
	IF EXISTS (SELECT 1 FROM #fc_probe) SET @ok = 0;
	IF @expected_summary = 0 AND @summary IS NOT NULL SET @ok = 0;
	IF @expected_summary = 1
	BEGIN
		SET @expected_pattern = CONCAT(@expected_exec, N' tests of % executed.');
		IF @expected_exec > 0 SET @expected_pattern += CONCAT(N' Succeded: ', @expected_success,
			N', failed: ', @expected_fail, N', errors: ', @expected_errors);
		ELSE SET @expected_pattern += N'%';
		IF @summary IS NULL OR @summary NOT LIKE @expected_pattern SET @ok = 0;
	END;
	IF EXISTS (SELECT 1 FROM #fc_audit WHERE kind = 'log' AND severity = 'Info'
		AND (proc_id IS NULL OR proc_id <> @run_id)) SET @ok = 0;
	IF @callback = 1 AND EXISTS (SELECT 1 FROM #fc_audit WHERE kind = 'log' AND severity = 'debug'
		AND (proc_id IS NULL OR proc_id <> @run_id OR row_count IS NULL OR row_count <> 1)) SET @ok = 0;
	IF @expected_code = 70000
	BEGIN
		IF CAST(SERVERPROPERTY('EngineEdition') AS int) = 11
		BEGIN
			IF CHARINDEX(N'Line:   N/A', ISNULL(@error, N'')) = 0 SET @ok = 0;
		END
		ELSE IF ISNULL(@error, N'') NOT LIKE N'%Line: [ 0-9][ 0-9][ 0-9][ 0-9][0-9] |%'
			SET @ok = 0;
	END;
	IF @expected_code = 70000 AND (SELECT COUNT(*) FROM #fc_audit WHERE kind = 'log' AND severity = 'error')
		<> @expected_fail + @expected_errors SET @ok = 0;
	IF EXISTS (SELECT 1 FROM #fc_audit WHERE kind = 'log' AND severity = 'error'
		AND (name IS NULL OR proc_id IS NULL)) SET @ok = 0;
	IF @logger = 'error' AND (SELECT COUNT(*) FROM #fc_audit WHERE kind = 'log' AND severity = 'error') <> 1
		SET @ok = 0;
	IF @callback_create = 1 AND OBJECT_ID(N'[tests].[test.run@fc_fixture_created]', N'P') IS NULL SET @ok = 0;
	INSERT #fc_report VALUES (@id, IIF(@ok = 1, 'PASS', 'FAIL'), CONVERT(varchar(8000),
		CONCAT(N'code=', @code, N'; executed=', @executed, N'; callbacks=', @before,
			N'; leaked transactions=', @leaked, N'; ', COALESCE(@error, @summary, N'No summary expected'))));
	SET @i += 1;
END;

DECLARE @raw_result nvarchar(max), @pattern_result int = -1, @rejected int = 0,
	@rejected_message nvarchar(max);
BEGIN TRY
	SET @raw_result = test.throw_error(N'123');
END TRY
BEGIN CATCH
	SELECT @rejected = ERROR_NUMBER(), @rejected_message = ERROR_MESSAGE();
END CATCH;
INSERT #fc_report VALUES ('numeric-only raw error message is rejected',
	IIF(@rejected = 245 AND CHARINDEX(N'Error: 123', COALESCE(@rejected_message, N'')) > 0, 'PASS', 'FAIL'),
	'throw_error must throw for a numeric-only message, not return the converted number.');
SET @rejected = 0;
SET @rejected_message = NULL;
BEGIN TRY
	THROW 51011, 'fc NULL pattern probe', 1;
END TRY
BEGIN CATCH
	BEGIN TRY
		SET @pattern_result = test.assert_error(
			N'NULL pattern skips the message filter', 51011, NULL, 1);
	END TRY
	BEGIN CATCH
		SELECT @rejected = ERROR_NUMBER(), @rejected_message = ERROR_MESSAGE();
	END CATCH;
END CATCH;
INSERT #fc_report VALUES ('NULL error pattern skips the message filter',
	IIF(@rejected = 0 AND @pattern_result IS NULL, 'PASS', 'FAIL'),
	'assert_error must accept an omitted message filter when number and state match.');

TRUNCATE TABLE #fc_audit;
UPDATE #fc_control SET require_before = 0, logger_failure = NULL;
SET @code = 0;
DECLARE @caller_transactions int = 0;
BEGIN TRAN;
BEGIN TRY
	EXEC test.run @test_names = N'[tests].[test.run@fc_fixture_a]', @log_proc_name = N'test.fc_observer';
END TRY
BEGIN CATCH
	SET @code = ERROR_NUMBER();
	SET @caller_transactions = @@TRANCOUNT;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
INSERT #fc_report VALUES ('reject caller transaction',
	IIF(@code = 70000 AND @caller_transactions = 1, 'PASS', 'FAIL'), 'Runner must reject, not execute or own the caller transaction.');

SET @code = 0;
SET @error = NULL;
BEGIN TRY
	EXEC [tests].[test.test@name_convention];
END TRY
BEGIN CATCH
	SET @code = ERROR_NUMBER();
	SET @error = ERROR_MESSAGE();
END CATCH;
INSERT #fc_report VALUES ('naming convention detects nonexistent target',
	IIF(@code = 245 AND CHARINDEX(N'[tests].[private.test.run@fc_fixture_private]', ISNULL(@error, N'')) > 0, 'PASS', 'FAIL'),
	CONVERT(varchar(8000), COALESCE(@error, N'Naming assertion did not reject the nonexistent private target')));

DECLARE @regressions nvarchar(max) = N'[
 {"id":"JSON property order ignored","l":"{\"a\":1,\"b\":2}","r":"{\"b\":2,\"a\":1}","correct":1},
 {"id":"JSON numeric spelling significant","l":"[1,1.0,1e0]","r":"[1.000,1e+0,1]","correct":0},
 {"id":"JSON row order significant","l":"[{\"id\":1},{\"id\":2}]","r":"[{\"id\":2},{\"id\":1}]","correct":0}
]';
SET @i = 0;
DECLARE @l nvarchar(max), @r nvarchar(max), @correct bit, @actual bit;
WHILE @i < 3
BEGIN
	SELECT @id = id, @l = l, @r = r, @correct = correct
	FROM OPENJSON(@regressions, CONCAT('$[', @i, ']'))
	WITH (id varchar(100), l nvarchar(max), r nvarchar(max), correct bit);
	SET @code = 0;
	BEGIN TRY
		SET @actual = test.is_equal(@l, @r);
	END TRY
	BEGIN CATCH
		SET @code = ERROR_NUMBER();
	END CATCH;
	INSERT #fc_report VALUES (@id,
		IIF(@code = 0 AND @actual = @correct, 'PASS', 'FAIL'),
		CONCAT('Actual=', @actual, '; semantic expectation=', @correct,
			'; ordered/raw OPENJSON comparison.'));
	SET @i += 1;
END;

TRUNCATE TABLE #fc_audit;
UPDATE #fc_control SET require_before = 1, logger_failure = NULL;
INSERT #fc_report VALUES ('duplicate without outer CATCH', 'PENDING',
	'Next batch intentionally emits duplicate errors; final batch checks continuation and single logging.');
GO
-- Intentionally outside TRY/CATCH: a caller CATCH would change the behavior being tested.
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
PRINT N'EXPECTED: duplicate-result errors 50000 in this batch. Continue through the final GO batch.';
EXEC test.run
	@test_names = N'[tests].[test.run@fc_fixture_a]|[tests].[test.run@fc_fixture_a]|[tests].[test.run@fc_fixture_a]',
	@before_callback = N'INSERT #fc_audit(kind) VALUES (''before'');',
	@log_proc_name = N'test.fc_observer';
END;
GO
-- Cleanup first, even when one of the preceding checks failed.
IF NOT EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
	DROP TABLE #fc_owned;
	DROP TABLE #fc_run;
	THROW 51090, 'Coverage stopped because preflight rejected this run.', 1;
END;
IF @@TRANCOUNT > 0 ROLLBACK;
DECLARE @owned_name nvarchar(512), @sql nvarchar(max);
WHILE EXISTS (SELECT 1 FROM #fc_owned)
BEGIN
	SELECT TOP (1) @owned_name = name FROM #fc_owned;
	SET @sql = N'DROP PROC IF EXISTS ' + @owned_name + N';';
	EXEC sys.sp_executesql @sql;
	DELETE #fc_owned WHERE name = @owned_name;
END;

DECLARE @executed int, @before int, @logged_errors int, @summary_count int;
SELECT @executed = COUNT(*) FROM #fc_audit WHERE kind = 'exec';
SELECT @before = COUNT(*) FROM #fc_audit WHERE kind = 'before';
SELECT @logged_errors = COUNT(*) FROM #fc_audit WHERE kind = 'log' AND severity = 'error'
	AND message = 'Duplicate test result';
SELECT @summary_count = COUNT(*) FROM #fc_audit WHERE kind = 'log' AND severity = 'Info'
	AND message LIKE '1 tests of % executed. Succeded: 1, failed: 0, errors: 0';
UPDATE #fc_report SET status = IIF(@executed = 3 AND @before = 3 AND @logged_errors = 2 AND @summary_count = 1, 'PASS', 'FAIL'),
	detail = CONCAT('executed=', @executed, '; callbacks=', @before, '; duplicate logs=', @logged_errors,
		'; expected 3,3,2 and one summary for the retained first result.')
WHERE scenario = 'duplicate without outer CATCH';

DECLARE @failed int, @bugs int, @checks int, @unique_checks int;
SELECT @checks = COUNT(*), @unique_checks = COUNT(DISTINCT scenario) FROM #fc_report;
-- Update this count when adding scenario groups: runner cases plus nine other groups.
IF @checks <> 49 OR @unique_checks <> 49
	INSERT #fc_report VALUES ('suite completeness', 'FAIL',
		CONCAT('Expected 49 unique scenario groups; got ', @checks, ' rows and ', @unique_checks,
			' distinct groups. An earlier batch may have failed or been skipped.'));
SELECT @failed = SUM(IIF(status <> 'PASS', 1, 0)),
	@bugs = SUM(IIF(status = 'KNOWN BUG', 1, 0)), @checks = COUNT(*) FROM #fc_report;
SELECT scenario, status, detail FROM #fc_report ORDER BY scenario;
SELECT IIF(@failed > 0, 'FAILED', 'PASSED') AS coverage_result,
	@checks AS scenario_groups, @failed AS failed_groups, @bugs AS known_bug_groups;
DROP TABLE #fc_audit;
DROP TABLE #fc_control;
DROP TABLE #fc_probe;
DROP TABLE #fc_report;
DROP TABLE #fc_owned;
DROP TABLE #fc_run;
IF @failed > 0 THROW 51099, 'Full coverage checks failed. Inspect the scenario/status/detail grid.', 1;
PRINT N'Full coverage functional checks completed.';
GO