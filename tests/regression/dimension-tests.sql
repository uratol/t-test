-- Run after install.sql in one clean, disposable database/session, outside a transaction.
-- Creates and removes its own dimension table and fixtures; restores saved vectors and scope.
SET NOCOUNT ON;
IF CAST(SERVERPROPERTY('EngineEdition') AS int) = 11
BEGIN
	PRINT N'SKIP: dimension-tests.sql requires session scope, which is not available on Fabric Warehouse. install.sql verifies global dimensions.';
	RETURN;
END;
IF @@TRANCOUNT > 0 OR OBJECT_ID(N'test.dimension', N'P') IS NULL
	THROW 51090, 'Install the framework and run this suite outside a transaction.', 1;
IF OBJECT_ID(N'[test].[test_dimension_values]', N'U') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#test_dimension_values') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#test_vectors') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#dt_seen') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#dt_log') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#dt_control') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#dt_report') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.run@dt_a]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.run@dt_b]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.run@dt_overflow]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[test].[dt_logger]', N'P') IS NOT NULL
	THROW 51090, 'Dimension fixture collision; use a clean disposable database/session.', 1;

DECLARE @previous_scope sql_variant, @current_scope sql_variant,
	@original_vectors nvarchar(max);
SELECT @previous_scope = SESSION_CONTEXT(N'ttest:vectors:scope');
SELECT @original_vectors = CONCAT(N'[', STRING_AGG(CONVERT(nvarchar(max),
	JSON_OBJECT('procedure_name': CONVERT(nvarchar(max), procedure_name),
		'parameters': CONVERT(nvarchar(max), parameters))), N','), N']')
FROM [test].[test_vectors];
CREATE TABLE #dt_seen (
	number decimal(28,4), text varchar(max) COLLATE Latin1_General_100_BIN2_UTF8, who varchar(8)
);
CREATE TABLE #dt_log (
	seq bigint, message varchar(max) COLLATE Latin1_General_100_BIN2_UTF8,
	data varchar(max) COLLATE Latin1_General_100_BIN2_UTF8
);
CREATE TABLE #dt_control (callbacks int);
CREATE TABLE #dt_report (scenario varchar(100), status varchar(8));
INSERT #dt_control VALUES (0);

BEGIN TRY
	EXEC sys.sp_executesql N'CREATE PROC [test].[dt_logger]
		@message nvarchar(max) = NULL, @data nvarchar(max) = NULL, @severity nvarchar(8) = N''debug'',
		@p1 sql_variant = NULL, @p2 sql_variant = NULL, @p3 sql_variant = NULL, @p4 sql_variant = NULL,
		@p1_str nvarchar(max) = NULL, @p2_str nvarchar(max) = NULL,
		@p3_str nvarchar(max) = NULL, @p4_str nvarchar(max) = NULL,
		@proc_id int = NULL, @rowcount int = NULL
	AS
	SET NOCOUNT ON;
	INSERT #dt_log SELECT COALESCE(MAX(seq), 0) + 1, @message, @data FROM #dt_log;';
	EXEC sys.sp_executesql N'CREATE PROC [tests].[test.run@dt_a]
		@number decimal(28,4) = 7, @text nvarchar(max) = N''default'',
		@mode nvarchar(8) = N''pass'', @who nvarchar(8) = N''a''
	AS
	SET NOCOUNT ON;
	INSERT #dt_seen VALUES (@number, @text, @who);
	IF @mode = N''fail'' BEGIN
		DECLARE @failure int = test.fail(N''dt assertion failure'');
	END;
	IF @mode = N''error'' THROW 51071, ''dt unexpected error'', 1;
	IF @mode = N''rollback'' BEGIN TRAN;
	IF @mode = N''rollback'' ROLLBACK;';
	EXEC sys.sp_executesql N'CREATE PROC [tests].[test.run@dt_b]
		@number decimal(28,4) = 7, @text nvarchar(max) = N''default''
	AS EXEC [tests].[test.run@dt_a] @number, @text, @who = N''b'';';

	DECLARE @scope nvarchar(7) = N'global', @pass int = 0, @code int, @sql nvarchar(max),
		@target nvarchar(max) = N'[tests].[test.run@dt_a]', @names nvarchar(max),
		@callback nvarchar(max) = N'UPDATE #dt_control SET callbacks += 1;',
		@values nvarchar(max), @long_text nvarchar(max), @expected_call nvarchar(max),
		@invalid nvarchar(max), @i int, @parameter nvarchar(128);

	-- Arrange
	EXEC test.set_registration_scope N'global';

	-- Act
	EXEC test.dimension NULL, NULL, NULL;
	EXEC test.run N'[tests].[replicate@dimensions]', @log_proc_name = N'test.dt_logger';

	-- Assert
	INSERT #dt_report VALUES ('missing global table warns/skips; static fallback', 'PASS');

	-- Arrange
	EXEC test.set_registration_scope N'session';

	-- Act
	EXEC test.dimension NULL, NULL, NULL;
	EXEC test.clear_registrations;

	-- Assert
	INSERT #dt_report VALUES ('missing session tables warn/skip; reset is a no-op', 'PASS');

	CREATE TABLE [test].[test_dimension_values] (
		procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
	);
	CREATE TABLE #test_dimension_values (
		procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
	);
	CREATE TABLE #test_vectors (
		procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
	);

	WHILE @pass < 2
	BEGIN
		-- Arrange
		EXEC test.set_registration_scope @scope;
		EXEC test.clear_registrations;
		IF @pass = 0
			EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = NULL;
		TRUNCATE TABLE #dt_seen;
		EXEC test.vector @target, N'1,N''a''';
		EXEC test.vector @target, N'2,N''bb''';

		-- Act
		EXEC test.run @target, @log_proc_name = N'test.dt_logger';

		-- Assert
		IF (SELECT COUNT(*) FROM #dt_seen) <> 2
			THROW 51091, 'Quick start did not execute two explicit vectors.', 1;

		-- Register in reverse parameter order; named binding must not depend on it.
		-- Arrange
		EXEC test.dimension @target, N'@text', N'["a","bb","ccc"]';
		EXEC test.dimension @target, N'@number', N'[1,2]';
		TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;
		UPDATE #dt_control SET callbacks = 0;

		-- Act
		EXEC test.run @target, @before_each_sql = @callback, @log_proc_name = N'test.dt_logger';

		-- Assert
		IF (SELECT COUNT(*) FROM #dt_seen) <> 8 OR (SELECT callbacks FROM #dt_control) <> 8
			OR (SELECT COUNT(*) FROM #dt_seen WHERE number = 1 AND text = 'a') <> 2
			OR (SELECT COUNT(*) FROM #dt_seen WHERE number = 2 AND text = 'bb') <> 2
			OR (SELECT COUNT(*) FROM #dt_log WHERE message LIKE 'Completed exec% PASS') <> 8
			OR NOT EXISTS (SELECT 1 FROM #dt_log
				WHERE message = '1 procedures selected. Planned cases: 8, executed cases: 8. Succeded: 8, failed: 0, errors: 0')
			THROW 51091, 'Quick start, duplicate calls, callbacks or summary failed.', 1;
		IF EXISTS (
			SELECT number, text FROM #dt_seen
			EXCEPT SELECT n.number, t.text FROM (VALUES (1), (2)) n(number)
				CROSS JOIN (VALUES ('a'), ('bb'), ('ccc')) t(text))
			OR (SELECT COUNT(*) FROM (SELECT number, text FROM #dt_seen GROUP BY number, text) c) <> 6
			THROW 51091, 'The product omitted or added a combination.', 1;
		INSERT #dt_report VALUES (CONCAT(@scope, ': 2 vectors + 2x3 dimensions; callbacks and duplicate calls'), 'PASS');

		-- Arrange
		EXEC test.dimension N'[tests].[test.run@dt_b]', N'@number', N'[101,102]';
		EXEC test.vector N'[tests].[test.run@dt_b]', N'103';
		SET @names = @target + N'|[tests].[test.run@dt_b]';
		TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;

		-- Act
		EXEC test.run @names, @log_proc_name = N'test.dt_logger';

		-- Assert
		IF (SELECT COUNT(*) FROM #dt_seen) <> 11
			OR (SELECT COUNT(*) FROM #dt_seen WHERE who = 'b' AND number IN (101,102,103)) <> 3
			OR (SELECT MAX(seq) FROM #dt_log WHERE message LIKE 'Start exec source=explicit%')
				>= (SELECT MIN(seq) FROM #dt_log WHERE message LIKE 'Start exec source=dimension%')
			THROW 51091, 'Global phase order or per-procedure dimension filtering failed.', 1;
		INSERT #dt_report VALUES (CONCAT(@scope, ': interleaved procedures; all vectors before dimensions'), 'PASS');

		-- Arrange
		EXEC test.dimension @target, N'@who', N'["x","y"]';
		TRUNCATE TABLE #dt_seen;

		-- Act
		EXEC test.run @target, @log_proc_name = N'test.dt_logger';

		-- Assert
		IF (SELECT COUNT(*) FROM #dt_seen) <> 14
			OR (SELECT COUNT(*) FROM #dt_seen WHERE who = 'x') <> 6
			OR (SELECT COUNT(*) FROM #dt_seen WHERE who = 'y') <> 6
			THROW 51091, 'Three dimensions did not generate 2x3x2 cases.', 1;
		INSERT #dt_report VALUES (CONCAT(@scope, ': arbitrary three-dimension product'), 'PASS');

		-- Arrange
		TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;
		SET @sql = N'EXEC test.set_registration_scope N''' + IIF(@scope = N'global', N'session', N'global') + N'''; EXEC test.clear_registrations;';

		-- Act
		EXEC test.run @target, @before_each_sql = @sql, @log_proc_name = N'test.dt_logger';

		-- Assert
		IF (SELECT COUNT(*) FROM #dt_seen) <> 14
			THROW 51091, 'Callback scope changes altered the frozen cases.', 1;

		-- Arrange
		EXEC test.set_registration_scope @scope;
		TRUNCATE TABLE #dt_seen;

		-- Act
		EXEC test.run @target, @before_each_sql = N'EXEC test.clear_registrations;', @log_proc_name = N'test.dt_logger';

		-- Assert
		IF (SELECT COUNT(*) FROM #dt_seen) <> 14
			THROW 51091, 'Reset inside a callback changed the active snapshot.', 1;
		INSERT #dt_report VALUES (CONCAT(@scope, ': frozen across callback scope switch/reset'), 'PASS');

		SET @scope = N'session';
		SET @pass += 1;
	END;

	-- Arrange
	EXEC test.set_registration_scope N'session';
	EXEC test.clear_registrations;
	SET @values = NCHAR(9) + NCHAR(13) + NCHAR(10) + N' [1.2500,-0,1e-4,9223372036854775807]';

	-- Act
	EXEC test.dimension @target, N'@number', @values;

	-- Assert
	IF NOT EXISTS (SELECT 1 FROM #test_dimension_values WHERE value = '1.2500')
		OR NOT EXISTS (SELECT 1 FROM #test_dimension_values WHERE value = '1e-4')
		OR NOT EXISTS (SELECT 1 FROM #test_dimension_values WHERE value = '9223372036854775807')
		THROW 51091, 'Numeric spelling was converted or JSON whitespace was rejected.', 1;

	-- Arrange
	TRUNCATE TABLE #dt_seen;

	-- Act
	EXEC test.run @target, @log_proc_name = N'test.dt_logger';

	-- Assert
	IF (SELECT COUNT(*) FROM #dt_seen) <> 4 OR NOT EXISTS
		(SELECT 1 FROM #dt_seen WHERE number = 9223372036854775807)
		THROW 51091, 'SQL numeric conversion lost precision.', 1;
	INSERT #dt_report VALUES ('JSON whitespace, numeric spelling, exponent and BIGINT precision', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	SET @long_text = REPLICATE(CONVERT(nvarchar(max), N'x'), 7000)
		+ NCHAR(381) + NCHAR(0x4E2D) + N'O''Brien, Jr.' + NCHAR(9) + NCHAR(13) + NCHAR(10) + N'  ';
	SET @values = N'["' + STRING_ESCAPE(@long_text, 'json') + N'"]';
	EXEC test.dimension @target, N'@text', @values;
	TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;

	-- Act
	EXEC test.run @target, @log_proc_name = N'test.dt_logger';

	-- Assert
	SET @expected_call = N'EXEC ' + @target + N' @text = N''' + REPLACE(@long_text, N'''', N'''''') + N''';';
	IF NOT EXISTS (SELECT 1 FROM #dt_seen WHERE
			CONVERT(varbinary(max), CONVERT(nvarchar(max), text)) = CONVERT(varbinary(max), @long_text))
		OR (SELECT COUNT(*) FROM #dt_log WHERE
			CONVERT(varbinary(max), CONVERT(nvarchar(max), data)) = CONVERT(varbinary(max), @expected_call)) <> 2
		THROW 51091, 'Long Unicode text or full replay logs changed.', 1;
	INSERT #dt_report VALUES ('long Unicode, apostrophes, controls, trailing spaces and full call logs', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	EXEC test.dimension @target, N'@text', N'[null,"NULL","GETDATE()","","a\"b","c\\d","same","same"]';
	TRUNCATE TABLE #dt_seen;

	-- Act
	EXEC test.run @target, @log_proc_name = N'test.dt_logger';

	-- Assert
	IF (SELECT COUNT(*) FROM #dt_seen) <> 8
		OR (SELECT COUNT(*) FROM #dt_seen WHERE text IS NULL) <> 1
		OR (SELECT COUNT(*) FROM #dt_seen WHERE text = 'NULL') <> 1
		OR (SELECT COUNT(*) FROM #dt_seen WHERE text = 'GETDATE()') <> 1
		OR (SELECT COUNT(*) FROM #dt_seen WHERE text = 'same') <> 2
		OR NOT EXISTS (SELECT 1 FROM #dt_seen WHERE DATALENGTH(text) = 0)
		OR NOT EXISTS (SELECT 1 FROM #dt_seen WHERE text = 'a"b')
		OR NOT EXISTS (SELECT 1 FROM #dt_seen WHERE text = 'c\d')
		THROW 51091, 'JSON string mapping, NULL or duplicate values changed.', 1;
	INSERT #dt_report VALUES ('NULL vs text, no expression evaluation, escaping and duplicate values', 'PASS');

	EXEC test.clear_registrations;
	SET @invalid = N'[
	 "EXEC test.dimension NULL,N''@number'',N''[1]'';",
	 "EXEC test.dimension N''[tempdb].[tests].[test.run@dt_a]'',N''@number'',N''[1]'';",
	 "EXEC test.dimension N''[test].[run]'',N''@number'',N''[1]'';",
	 "EXEC test.dimension N''[tests].[test.run@dt_a]'',N''@unknown'',N''[1]'';",
	 "EXEC test.dimension N''[tests].[test.run@dt_a]'',N''number'',N''[1]'';",
	 "EXEC test.dimension N''[tests].[test.run@dt_a]'',N''@number'',NULL;",
	 "EXEC test.dimension N''[tests].[test.run@dt_a]'',N''@number'',N'''';",
	 "EXEC test.dimension N''[tests].[test.run@dt_a]'',N''@number'',N''oops'';",
	 "EXEC test.dimension N''[tests].[test.run@dt_a]'',N''@number'',N''{}'';",
	 "EXEC test.dimension N''[tests].[test.run@dt_a]'',N''@number'',N''[]'';"
	]';
	SET @i = 0;
	WHILE @i < (SELECT COUNT(*) FROM OPENJSON(@invalid))
	BEGIN
		-- Arrange
		SELECT @sql = value FROM OPENJSON(@invalid) WHERE CONVERT(int, [key]) = @i;
		SET @code = 0;

		-- Act
		BEGIN TRY EXEC sys.sp_executesql @sql; END TRY
		BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

		-- Assert
		IF @code <> 70000 OR EXISTS (SELECT 1 FROM #test_dimension_values)
			THROW 51091, 'Invalid dimension registration was accepted or left rows.', 1;
		SET @i += 1;
	END;

	-- Arrange
	EXEC test.dimension @target, N'@number', N'[1,2]';
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.dimension @target, N'@number', N'[3]'; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 70000 OR (SELECT COUNT(*) FROM #test_dimension_values) <> 2
		THROW 51091, 'Duplicate domain replaced or appended rows.', 1;
	INSERT #dt_report VALUES ('invalid names/JSON/empty domain; duplicate registration preserves rows', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.dimension @target, N'@number', N'[1,true]'; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 515 OR EXISTS (SELECT 1 FROM #test_dimension_values)
		THROW 51091, 'Unsupported JSON type did not fail atomically with a native error.', 1;
	INSERT #dt_report VALUES ('one atomic INSERT; unsupported types use native NOT NULL errors', 'PASS');

	SET @invalid = N'["a\u0000b","\uD800","\uDC00"]';
	SET @i = 0;
	WHILE @i < 3
	BEGIN
		-- Arrange
		SELECT @values = CONCAT(N'["', STRING_ESCAPE(value, 'json'), N'"]')
		FROM OPENJSON(@invalid) WHERE CONVERT(int, [key]) = @i;
		SET @code = 0;

		-- Act
		BEGIN TRY EXEC test.dimension @target, N'@text', @values; END TRY
		BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

		-- Assert
		IF @code <> 515 OR EXISTS (SELECT 1 FROM #test_dimension_values)
			THROW 51091, 'NUL or invalid Unicode was silently removed or replaced.', 1;
		SET @i += 1;
	END;
	INSERT #dt_report VALUES ('SQL-unrepresentable NUL and invalid Unicode are rejected atomically', 'PASS');

	-- Arrange
	SET @values = N'["' + REPLICATE(CONVERT(nvarchar(max), NCHAR(39)), 8388607) + N'"]';
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.dimension @target, N'@text', @values; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 515 OR EXISTS (SELECT 1 FROM #test_dimension_values)
		THROW 51091, 'UTF-8 literal size was not checked after SQL escaping.', 1;
	SET @values = NULL;
	INSERT #dt_report VALUES ('shared UTF-8 literal limit is checked after escaping', 'PASS');

	-- Arrange
	SET @values = N'["' + REPLICATE(CONVERT(nvarchar(max), N'x'), 8388608) + N'"]';
	EXEC test.dimension @target, N'@text', @values;
	EXEC test.dimension @target, N'@who', @values;
	SET @values = NULL;
	TRUNCATE TABLE #dt_seen;
	UPDATE #dt_control SET callbacks = 0;
	SET @code = 0;

	-- Act
	BEGIN TRY
		EXEC test.run @target, @before_each_sql = N'UPDATE #dt_control SET callbacks += 1;',
			@log_proc_name = N'test.dt_logger';
	END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 515 OR (SELECT callbacks FROM #dt_control) <> 0 OR EXISTS (SELECT 1 FROM #dt_seen)
		THROW 51091, 'Oversized generated arguments reached a callback or test.', 1;
	EXEC test.clear_registrations;
	INSERT #dt_report VALUES ('shared generated-argument size limit aborts before invocation', 'PASS');

	-- Arrange
	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = N'invalid';
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.dimension NULL, NULL, NULL; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 70000 THROW 51091, 'Invalid captured scope was ignored.', 1;
	EXEC test.set_registration_scope N'session';
	INSERT #dt_report VALUES ('dimension registration rejects invalid session context', 'PASS');

	-- Arrange
	EXEC test.dimension @target, N'@mode', N'["fail","error","pass"]';
	TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.run @target, @log_proc_name = N'test.dt_logger'; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 70000
		OR NOT EXISTS (SELECT 1 FROM #dt_log WHERE message LIKE 'Completed exec source=dimension% FAILED')
		OR NOT EXISTS (SELECT 1 FROM #dt_log WHERE message LIKE 'Completed exec source=dimension% ERROR')
		OR NOT EXISTS (SELECT 1 FROM #dt_log WHERE message LIKE '%Succeded: 1, failed: 1, errors: 1')
		THROW 51091, 'Dimension outcomes were misclassified.', 1;
	INSERT #dt_report VALUES ('dimension assertion, unexpected error and success classification', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	EXEC test.vector @target, N'@mode=N''fail''';
	EXEC test.dimension @target, N'@mode', N'["fail","fail","fail"]';
	TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.run @target, @max_failures = 2, @log_proc_name = N'test.dt_logger'; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 70000 OR (SELECT COUNT(*) FROM #dt_seen) <> 2
		OR (SELECT COUNT(*) FROM #dt_log WHERE message LIKE 'Completed exec% FAILED') <> 2
		OR NOT EXISTS (SELECT 1 FROM #dt_log WHERE message LIKE '%Planned cases: 4, executed cases: 2.%failed: 2, errors: 0')
		THROW 51091, 'Failure limit did not span both phases or lost completion.', 1;
	INSERT #dt_report VALUES ('failure limit spans explicit/dimension phases and logs completion', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	EXEC test.dimension @target, N'@mode', N'["rollback","rollback"]';
	TRUNCATE TABLE #dt_seen;

	-- Act
	EXEC test.run @target, @log_proc_name = N'test.dt_logger';

	-- Assert
	IF @@TRANCOUNT <> 0 OR (SELECT COUNT(*) FROM #dt_seen) <> 2
		THROW 51091, 'Test-owned rollback damaged the private queue.', 1;
	INSERT #dt_report VALUES ('test-owned rollback preserves frozen dimensions and queue', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	EXEC test.dimension @target, N'@number', N'[1,2]';
	SET @names = @target + N'|' + @target;
	TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.run @names, @log_proc_name = N'test.dt_logger'; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 50000 OR (SELECT COUNT(*) FROM #dt_seen) <> 3
		OR (SELECT COUNT(*) FROM #dt_log WHERE message LIKE 'Completed exec%') <> 2
		THROW 51091, 'Dimension cases bypassed legacy duplicate-selection timing.', 1;
	INSERT #dt_report VALUES ('dimension-only duplicate selection preserves legacy attempt timing', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	EXEC test.dimension @target, N'@number', N'["not-a-number"]';
	TRUNCATE TABLE #dt_seen; TRUNCATE TABLE #dt_log;
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.run @target, @log_proc_name = N'test.dt_logger'; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 70000 OR EXISTS (SELECT 1 FROM #dt_seen)
		OR NOT EXISTS (SELECT 1 FROM #dt_log WHERE message LIKE 'Completed exec source=dimension% ERROR')
		THROW 51091, 'Conversion failure was not an attempted, unexpected case error.', 1;
	INSERT #dt_report VALUES ('dimension conversion errors are unexpected errors, not assertions', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	SET @sql = N'CREATE PROC [tests].[test.run@dt_overflow] ';
	SET @i = 0;
	WHILE @i < 63
	BEGIN
		SET @sql += IIF(@i = 0, N'', N',') + CONCAT(N'@p', @i, N' int = 0');
		SET @i += 1;
	END;
	SET @sql += N' AS RETURN;';
	EXEC sys.sp_executesql @sql;
	SET @i = 0;
	WHILE @i < 62
	BEGIN
		SET @parameter = CONCAT(N'@p', @i);
		EXEC test.dimension N'[tests].[test.run@dt_overflow]', @parameter, N'[0,1]';
		SET @i += 1;
	END;
	EXEC test.vector N'[tests].[test.run@dt_overflow]', N'@p0=0';
	SET @callback = N'UPDATE #dt_control SET callbacks += 1; THROW 51073, ''dt stop before materialization'', 1;';
	UPDATE #dt_control SET callbacks = 0;
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.run N'[tests].[test.run@dt_overflow]', @before_each_sql = @callback; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 51073 OR (SELECT callbacks FROM #dt_control) <> 1
		THROW 51091, 'Valid BIGINT planning was rejected or generated prematurely.', 1;

	-- Arrange
	UPDATE #dt_control SET callbacks = 0;
	SET @code = 0;

	-- Act
	BEGIN TRY
		EXEC test.run N'[tests].[test.run@dt_overflow]|[tests].[test.run@dt_overflow]', @before_each_sql = @callback;
	END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 70000 OR (SELECT callbacks FROM #dt_control) <> 0
		THROW 51091, 'Run-total BIGINT overflow was not rejected before callbacks.', 1;

	-- Arrange
	EXEC test.dimension N'[tests].[test.run@dt_overflow]', N'@p62', N'[0,1]';
	SET @code = 0;

	-- Act
	BEGIN TRY EXEC test.run N'[tests].[test.run@dt_overflow]', @before_each_sql = @callback; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;

	-- Assert
	IF @code <> 70000 OR (SELECT callbacks FROM #dt_control) <> 0
		THROW 51091, 'Product BIGINT overflow was not rejected before callbacks.', 1;
	INSERT #dt_report VALUES ('BIGINT valid/product-overflow/total-overflow checks without huge products', 'PASS');

	-- Arrange
	EXEC test.dimension @target, N'@number', N'[1]';
	TRUNCATE TABLE #dt_seen;

	-- Act
	EXEC test.run @test_names = N'[tests].[test.run@dt_overflow]|[tests].[test.run@dt_a]',
		@exclude_test_names = N'[tests].[test.run@dt_overflow]', @log_proc_name = N'test.dt_logger';

	-- Assert
	IF (SELECT COUNT(*) FROM #dt_seen) <> 1
		THROW 51091, 'Excluded registrations blocked the selected test.', 1;
	INSERT #dt_report VALUES ('excluded overflowing definitions do not enter preflight', 'PASS');

	-- Arrange
	EXEC test.clear_registrations;
	EXEC test.dimension @target, N'@text', N'["session"]';
	EXEC test.set_registration_scope N'global';
	EXEC test.dimension @target, N'@text', N'["global"]';
	TRUNCATE TABLE #dt_seen;

	-- Act
	EXEC test.run @target, @log_proc_name = N'test.dt_logger';

	-- Assert
	IF (SELECT COUNT(*) FROM #dt_seen) <> 1 OR NOT EXISTS (SELECT 1 FROM #dt_seen WHERE text = 'global')
		THROW 51091, 'The runner merged scopes.', 1;

	-- Arrange
	--N/A

	-- Act
	EXEC test.clear_registrations;

	-- Assert
	SELECT @current_scope = SESSION_CONTEXT(N'ttest:vectors:scope');
	IF EXISTS (SELECT 1 FROM [test].[test_dimension_values])
		OR NOT EXISTS (SELECT 1 FROM #test_dimension_values)
		OR CONVERT(nvarchar(7), @current_scope) <> N'global'
		THROW 51091, 'Reset changed the other store or the scope.', 1;
	INSERT #dt_report VALUES ('selected-store-only reads and reset; scope retained', 'PASS');

	SET @pass = 0;
	SET @scope = N'global';
	SET @names = @target + N'|[tests].[test.run@dt_b]';
	WHILE @pass < 2
	BEGIN
		-- Arrange
		EXEC test.set_registration_scope @scope;
		EXEC test.clear_registrations;
		EXEC test.vector @target, N'1';
		EXEC test.dimension @target, N'@number', N'[1]';
		EXEC test.vector N'[tests].[test.run@dt_b]', N'2';
		EXEC test.dimension N'[tests].[test.run@dt_b]', N'@number', N'[2]';
		SET @code = 0;

		-- Act
		BEGIN TRY
			EXEC test.clear_registrations N'[tests].[test.run@dt_missing]';
		END TRY
		BEGIN CATCH
			SET @code = ERROR_NUMBER();
		END CATCH;
		TRUNCATE TABLE #dt_seen;
		EXEC test.run @names, @log_proc_name = N'test.dt_logger';

		-- Assert
		IF @code <> 70000 OR (SELECT COUNT(*) FROM #dt_seen) <> 4
			THROW 51091, 'Invalid targeted reset changed registrations or was accepted.', 1;

		-- Arrange
		--N/A

		-- Act
		EXEC test.clear_registrations @test_name = N'tests.[test.run@dt_a]';
		SELECT @current_scope = SESSION_CONTEXT(N'ttest:vectors:scope');
		TRUNCATE TABLE #dt_seen;
		EXEC test.run @names, @log_proc_name = N'test.dt_logger';

		-- Assert
		IF (SELECT COUNT(*) FROM #dt_seen) <> 3
			OR (SELECT COUNT(*) FROM #dt_seen WHERE who = 'a' AND number = 7) <> 1
			OR (SELECT COUNT(*) FROM #dt_seen WHERE who = 'b' AND number = 2) <> 2
			OR CONVERT(nvarchar(7), @current_scope) <> @scope
			THROW 51091, 'Targeted reset did not clear both sources for only the resolved test.', 1;
		IF @pass = 1 AND (
			NOT EXISTS (SELECT 1 FROM [test].[test_vectors] WHERE procedure_name = '[tests].[test.run@dt_b]')
			OR NOT EXISTS (SELECT 1 FROM [test].[test_dimension_values] WHERE procedure_name = '[tests].[test.run@dt_b]'))
			THROW 51091, 'Session targeted reset changed global registrations.', 1;
		IF @pass = 0 AND NOT EXISTS (SELECT 1 FROM #test_dimension_values WHERE procedure_name = @target)
			THROW 51091, 'Global targeted reset changed session registrations.', 1;
		INSERT #dt_report VALUES (CONCAT(@scope, ': targeted reset preserves other tests/scope; rejects unknown test'), 'PASS');
		SET @scope = N'session';
		SET @pass += 1;
	END;

	DROP PROCEDURE [tests].[test.run@dt_a];
	DROP PROCEDURE [tests].[test.run@dt_b];
	DROP PROCEDURE [tests].[test.run@dt_overflow];
	DROP PROCEDURE [test].[dt_logger];
	DROP TABLE [test].[test_dimension_values];
	DROP TABLE #test_dimension_values; DROP TABLE #test_vectors;
	DELETE FROM [test].[test_vectors];
	INSERT [test].[test_vectors] (procedure_name, parameters)
	SELECT procedure_name, parameters FROM OPENJSON(@original_vectors)
		WITH (procedure_name nvarchar(max), parameters nvarchar(max));
	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
	SELECT scenario, status FROM #dt_report ORDER BY scenario;
	SELECT 'PASSED' AS dimension_result, COUNT(*) AS scenario_groups, 0 AS failed_groups FROM #dt_report;
	DROP TABLE #dt_seen; DROP TABLE #dt_log; DROP TABLE #dt_control; DROP TABLE #dt_report;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;
	DROP PROCEDURE IF EXISTS [tests].[test.run@dt_a];
	DROP PROCEDURE IF EXISTS [tests].[test.run@dt_b];
	DROP PROCEDURE IF EXISTS [tests].[test.run@dt_overflow];
	DROP PROCEDURE IF EXISTS [test].[dt_logger];
	DROP TABLE IF EXISTS [test].[test_dimension_values];
	DROP TABLE IF EXISTS #test_dimension_values; DROP TABLE IF EXISTS #test_vectors;
	DELETE FROM [test].[test_vectors];
	INSERT [test].[test_vectors] (procedure_name, parameters)
	SELECT procedure_name, parameters FROM OPENJSON(@original_vectors)
		WITH (procedure_name nvarchar(max), parameters nvarchar(max));
	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
	DROP TABLE #dt_seen; DROP TABLE #dt_log; DROP TABLE #dt_control; DROP TABLE #dt_report;
	THROW;
END CATCH;
