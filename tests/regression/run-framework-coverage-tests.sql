-- Run installed framework tests and all 49 runner/framework scenario groups.
-- Run install.sql and install-framework-coverage-tests.sql beforehand.
-- Execute every GO batch in ONE dedicated test-database session.
-- Does not install persistent tests or register vectors/dimensions.
-- Disposable observers/fixtures are created and cleaned by this run only.
-- Expected duplicate errors appear in Messages; the final result grid is authoritative.
SET NOCOUNT ON;
-- A failed preflight must also block fixture creation/cleanup in later GO batches.
DROP TABLE IF EXISTS #fc_run;
DROP TABLE IF EXISTS #fc_owned;
CREATE TABLE #fc_run (ready bit, positive_tests nvarchar(max));
CREATE TABLE #fc_owned (name nvarchar(512));
INSERT #fc_run VALUES (0, NULL);
IF @@TRANCOUNT > 0
	THROW 51090, 'Run the coverage script outside a transaction.', 1;
IF OBJECT_ID(N'test.run', N'P') IS NULL OR OBJECT_ID(N'test.is_equal', N'FN') IS NULL
	OR OBJECT_ID(N'test.fail_no_error', N'P') IS NULL
	OR OBJECT_ID(N'test.assert_error', N'P') IS NULL
	OR OBJECT_ID(N'test.set_registration_scope', N'P') IS NULL
	OR OBJECT_ID(N'test.vector', N'P') IS NULL
	THROW 51090, 'Install the framework before running coverage tests.', 1;
IF OBJECT_ID(N'tempdb..#test_vectors') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#test_dimension_values') IS NOT NULL
	THROW 51090, 'Coverage requires no caller registration tables; their contents will not be changed.', 1;
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
-- Persistent test definitions and factory vectors must already be installed.
IF OBJECT_ID(N'test.test_vectors', N'U') IS NULL
    THROW 51090, 'Run install.sql and install-framework-coverage-tests.sql first.', 1;
-- Select only positive shipped tests: broad schema discovery would include error probes
-- and unrelated user tests. Keep this single list for both preflight and execution.
DECLARE @positive_names nvarchar(max) = N'[
    "[tests].[test.throw]",
    "[tests].[test.format_message]",
    "[tests].[test.test]",
    "[tests].[test.test@name_convention]",
    "[tests].[test.assert_equals]",
    "[tests].[test.assert_not_null]",
    "[tests].[test.assert_null]",
    "[tests].[test.is_equal]",
    "[tests].[sys.objects@tables]",
    "[tests].[stdev@basic]",
    "[tests].[data_types@basic]",
    "[tests].[test.assert_float_equals]",
    "[tests].[test.assert_resultset_equals]",
    "[tests].[test.assert_query_schemas_equal]",
    "[tests].[test.assert_error]",
    "[tests].[power@vectors]",
    "[tests].[replicate@dimensions]",
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
    @missing_required nvarchar(max), @required_message nvarchar(2048),
    @required_index int = 0, @required_name nvarchar(512),
    @required_parameters nvarchar(max);
SELECT @missing_required = STRING_AGG(CONVERT(nvarchar(max), value), N', ')
FROM OPENJSON(@positive_names)
WHERE OBJECT_ID(value, N'P') IS NULL;
IF @missing_required IS NOT NULL
BEGIN
    SET @required_message = N'Run install-framework-coverage-tests.sql first. Missing tests: '
        + @missing_required;
    THROW 51090, @required_message, 1;
END;
WHILE @required_index < (SELECT COUNT(*) FROM OPENJSON(@required_vectors))
BEGIN
    SELECT @required_name = procedure_name, @required_parameters = parameters
    FROM OPENJSON(@required_vectors, CONCAT('$[', @required_index, ']'))
    WITH (procedure_name nvarchar(512), parameters nvarchar(max));
    IF NOT EXISTS (
        SELECT 1 FROM [test].[test_vectors]
        WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2
            = @required_name COLLATE Latin1_General_100_BIN2
            AND CONVERT(nvarchar(max), parameters) COLLATE Latin1_General_100_BIN2
            = @required_parameters COLLATE Latin1_General_100_BIN2)
        THROW 51090, 'Required coverage vectors are missing. Rerun install-framework-coverage-tests.sql.', 1;
    SET @required_index += 1;
END;
UPDATE #fc_run SET ready = 1,
    positive_tests = (
        SELECT STRING_AGG(CONVERT(nvarchar(max), value), N'|')
        FROM OPENJSON(@positive_names)
    );
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
IF @mode = ''fail'' EXEC test.assert_equals N''fc intentional assertion failure'', N''expected'', N''actual'';
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
		IF @mode = ''number'' EXEC test.assert_error N''fc number mismatch'', 51012, DEFAULT, DEFAULT;
		ELSE EXEC test.assert_error N''fc pattern mismatch'', DEFAULT, N''%does not match%'', DEFAULT;
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
	THROW 51090, 'Coverage fixture preflight failed. Execution was skipped.', 1;
IF @@TRANCOUNT > 0 THROW 51090, 'Coverage fixture creation left an active transaction.', 1;
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

DECLARE @positive nvarchar(max) = (SELECT positive_tests FROM #fc_run),
	@code int = 0, @error nvarchar(max) = NULL, @summary nvarchar(max), @run_id int = OBJECT_ID(N'test.run');
DECLARE @positive_count int = (SELECT COUNT(*) FROM STRING_SPLIT(@positive, N'|'));
DECLARE @engine_edition int = CAST(SERVERPROPERTY('EngineEdition') AS int),
    @previous_scope sql_variant;
IF @engine_edition <> 11
    EXEC sys.sp_executesql N'SELECT @scope = SESSION_CONTEXT(N''ttest:vectors:scope'');',
        N'@scope sql_variant OUTPUT', @scope = @previous_scope OUTPUT;

-- Arrange
-- Read the installed global vectors; do not register or replace cases during a run.
BEGIN TRY
    EXEC test.set_registration_scope N'global';

    -- Act
    EXEC test.run @test_names = @positive, @log_proc_name = N'test.fc_observer';
END TRY
BEGIN CATCH
    SET @code = ERROR_NUMBER();
    SET @error = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH;
IF @engine_edition <> 11
    EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;

-- Assert
SELECT @summary = message FROM #fc_audit WHERE kind = 'log' AND severity = 'Info';
INSERT #fc_report VALUES ('positive unit tests and bundled tests',
	IIF(@code = 0 AND @summary = CONCAT(@positive_count, ' procedures selected. Planned cases: ',
		@positive_count + 8, ', executed cases: ', @positive_count + 8, '. Succeded: ',
		@positive_count + 8, ', failed: 0, errors: 0'), 'PASS', 'FAIL'),
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
	@names nvarchar(max), @exclude nvarchar(max), @test_object_schemas nvarchar(max), @exclude_test_object_schemas nvarchar(max),
	@limit int, @callback bit, @callback_error bit, @callback_transaction bit, @logger varchar(16),
	@discover bit, @trim_names bit, @default_logger bit, @callback_create bit, @logger_proc nvarchar(256),
	@expected_exec int, @expected_success int, @expected_fail int, @expected_errors int,
	@expected_code int, @expected_summary bit, @expected_before int,
	@before_each_sql nvarchar(max), @executed int, @before int, @leaked int, @ok bit,
	@expected_pattern nvarchar(max);
WHILE @i < @n
BEGIN
	-- Expected identities are independent of runner filtering.
	-- Arrange
	SELECT @id = id, @keys = names, @exclude_keys = exclude_names, @test_object_schemas = schemas,
		@expected_keys = COALESCE(expected_names, names), @expected_message = expected_message,
		@exclude_test_object_schemas = exclude_schemas, @limit = limit_failed, @callback = ISNULL(callback, 0),
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
		schemas nvarchar(max), exclude_schemas nvarchar(max), limit_failed int '$.limit',
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
	SET @before_each_sql = IIF(@callback = 1, N'INSERT #fc_audit(kind) VALUES (''before'');', NULL);
	IF @callback_error = 1 SET @before_each_sql = N'THROW 51016, ''fc intentional callback error'', 1;';
	IF @callback_transaction = 1 SET @before_each_sql =
		N'BEGIN TRAN; INSERT #fc_probe VALUES (1); THROW 51016, ''fc intentional callback error'', 1;';
	IF @callback_create = 1 SET @before_each_sql =
		N'EXEC(N''CREATE PROC [tests].[test.run@fc_fixture_created] AS RETURN 0;''); '
		+ N'INSERT #fc_owned VALUES (N''[tests].[test.run@fc_fixture_created]''); '
		+ N'INSERT #fc_audit(kind) VALUES (''before'');';
	SET @logger_proc = IIF(@default_logger = 1, NULL, N'test.fc_observer');
	SET @code = 0;
	SET @error = NULL;
	SET @leaked = 0;

	-- Act
	BEGIN TRY
		IF @discover = 1 AND EXISTS (SELECT 1 FROM test.test WHERE CHARINDEX(N'|', test_proc_full_name) > 0)
			THROW 51092, 'Cannot safely exclude existing pipe-named procedures from default discovery.', 1;
		EXEC test.run @test_names = @names, @exclude_test_names = @exclude,
			@test_object_schemas = @test_object_schemas, @exclude_test_object_schemas = @exclude_test_object_schemas, @max_failures = @limit,
			@before_each_sql = @before_each_sql, @log_proc_name = @logger_proc;
		SET @leaked = @@TRANCOUNT;
		IF @@TRANCOUNT > 0 ROLLBACK;
	END TRY
	BEGIN CATCH
		SET @code = ERROR_NUMBER();
		SET @error = ERROR_MESSAGE();
		SET @leaked = @@TRANCOUNT;
		IF @@TRANCOUNT > 0 ROLLBACK;
	END CATCH;

	-- Counts, identities/multiplicity, diagnostics and transaction cleanup.
	-- Assert
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

DECLARE @raw_result nvarchar(max), @pattern_accepted bit = 0, @rejected int = 0,
	@rejected_message nvarchar(max);

-- Arrange
--N/A

-- Act
BEGIN TRY
	SET @raw_result = test.throw_error(N'123');
END TRY
BEGIN CATCH
	-- Assert
	SELECT @rejected = ERROR_NUMBER(), @rejected_message = ERROR_MESSAGE();
END CATCH;

-- Assert
INSERT #fc_report VALUES ('numeric-only raw error message is rejected',
	IIF(@rejected = 245 AND CHARINDEX(N'Error: 123', COALESCE(@rejected_message, N'')) > 0, 'PASS', 'FAIL'),
	'throw_error must throw for a numeric-only message, not return the converted number.');

-- Arrange
SET @rejected = 0;
SET @rejected_message = NULL;

-- Act
BEGIN TRY
	THROW 51011, 'fc NULL pattern probe', 1;
END TRY
BEGIN CATCH
	-- Act
	BEGIN TRY
		EXEC test.assert_error
			N'NULL pattern skips the message filter', 51011, NULL, 1;
		SET @pattern_accepted = 1;
	END TRY
	BEGIN CATCH
		-- Assert
		SELECT @rejected = ERROR_NUMBER(), @rejected_message = ERROR_MESSAGE();
	END CATCH;

	-- Assert
END CATCH;
INSERT #fc_report VALUES ('NULL error pattern skips the message filter',
	IIF(@rejected = 0 AND @pattern_accepted = 1, 'PASS', 'FAIL'),
	'assert_error must accept an omitted message filter when number and state match.');

DECLARE @caller_transactions int = 0;

-- Arrange
TRUNCATE TABLE #fc_audit;
UPDATE #fc_control SET require_before = 0, logger_failure = NULL;
SET @code = 0;
BEGIN TRAN;

-- Act
BEGIN TRY
	EXEC test.run @test_names = N'[tests].[test.run@fc_fixture_a]', @log_proc_name = N'test.fc_observer';
END TRY
BEGIN CATCH
	SET @code = ERROR_NUMBER();
	SET @caller_transactions = @@TRANCOUNT;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- Assert
INSERT #fc_report VALUES ('reject caller transaction',
	IIF(@code = 70000 AND @caller_transactions = 1, 'PASS', 'FAIL'), 'Runner must reject, not execute or own the caller transaction.');

-- Arrange
SET @code = 0;
SET @error = NULL;

-- Act
BEGIN TRY
	EXEC [tests].[test.test@name_convention];
END TRY
BEGIN CATCH
	SET @code = ERROR_NUMBER();
	SET @error = ERROR_MESSAGE();
END CATCH;

-- Assert
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
	-- Arrange
	SELECT @id = id, @l = l, @r = r, @correct = correct
	FROM OPENJSON(@regressions, CONCAT('$[', @i, ']'))
	WITH (id varchar(100), l nvarchar(max), r nvarchar(max), correct bit);
	SET @code = 0;

	-- Act
	BEGIN TRY
		SET @actual = test.is_equal(@l, @r);
	END TRY
	BEGIN CATCH
		SET @code = ERROR_NUMBER();
	END CATCH;

	-- Assert
	INSERT #fc_report VALUES (@id,
		IIF(@code = 0 AND @actual = @correct, 'PASS', 'FAIL'),
		CONCAT('Actual=', @actual, '; semantic expectation=', @correct,
			'; ordered/raw OPENJSON comparison.'));
	SET @i += 1;
END;

-- Arrange
TRUNCATE TABLE #fc_audit;
UPDATE #fc_control SET require_before = 1, logger_failure = NULL;
INSERT #fc_report VALUES ('duplicate without outer CATCH', 'PENDING',
	'Next batch intentionally emits duplicate errors; final batch checks continuation and single logging.');
GO
-- Intentionally outside TRY/CATCH: a caller CATCH would change the behavior being tested.
IF EXISTS (SELECT 1 FROM #fc_run WHERE ready = 1)
BEGIN
PRINT N'EXPECTED: duplicate-result errors 50000 in this batch. Continue through the final GO batch.';

-- Act
EXEC test.run
	@test_names = N'[tests].[test.run@fc_fixture_a]|[tests].[test.run@fc_fixture_a]|[tests].[test.run@fc_fixture_a]',
	@before_each_sql = N'INSERT #fc_audit(kind) VALUES (''before'');',
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

-- Assert
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