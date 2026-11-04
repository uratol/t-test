-- Run after install.sql, outside a transaction, in one disposable test database/session.
-- Accepts only an empty registry or shipped POWER rows; restores those rows after the suite.
-- The last result grid is authoritative. Expected runner errors are caught.
SET NOCOUNT ON;
IF @@TRANCOUNT > 0
	THROW 51090, 'Run vector-tests.sql outside a transaction.', 1;
IF OBJECT_ID(N'test.vector', N'P') IS NULL OR OBJECT_ID(N'test.set_scope', N'P') IS NULL
	OR OBJECT_ID(N'test.reset', N'P') IS NULL
	OR OBJECT_ID(N'[test].[test_vectors]', N'U') IS NULL
	THROW 51090, 'Install the vector APIs before running this suite.', 1;
IF EXISTS (SELECT 1 FROM [test].[test_vectors]
	WHERE procedure_name COLLATE Latin1_General_100_BIN2_UTF8 <> '[tests].[power@vectors]'
		OR parameters COLLATE Latin1_General_100_BIN2_UTF8 NOT IN ('2,3,8', '3,2,9', '5,0,1', '-2,3,-8'))
	OR (SELECT COUNT(*) FROM [test].[test_vectors]) NOT IN (0, 4)
	OR (SELECT COUNT(DISTINCT parameters) FROM [test].[test_vectors])
		<> (SELECT COUNT(*) FROM [test].[test_vectors])
	OR OBJECT_ID(N'tempdb..#test_vectors') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#vt_exec') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#vt_log') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#vt_control') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#vt_probe') IS NOT NULL
	OR OBJECT_ID(N'tempdb..#vt_report') IS NOT NULL
	OR OBJECT_ID(N'[test].[vt_logger]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.run@vt_vector]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.run@vt_static]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.run@vt_required]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.run@vt_metadata]', N'P') IS NOT NULL
	THROW 51090, 'Vector fixture collision; use a clean disposable test database/session.', 1;

DECLARE @previous_scope sql_variant = SESSION_CONTEXT(N'ttest:vectors:scope');
DECLARE @global_table_id int = OBJECT_ID(N'[test].[test_vectors]', N'U');
DECLARE @original_vectors nvarchar(max);
SELECT @original_vectors = CONCAT(N'[', STRING_AGG(CONVERT(nvarchar(max),
	JSON_OBJECT('procedure_name': CONVERT(nvarchar(max), procedure_name),
		'parameters': CONVERT(nvarchar(max), parameters))), N','), N']')
FROM [test].[test_vectors];
CREATE TABLE #vt_exec (
	number int, text varchar(max) COLLATE Latin1_General_100_BIN2_UTF8, mode varchar(32)
);
CREATE TABLE #vt_log (
	message varchar(max) COLLATE Latin1_General_100_BIN2_UTF8,
	data varchar(max) COLLATE Latin1_General_100_BIN2_UTF8, severity varchar(8)
);
CREATE TABLE #vt_control (logger_failure varchar(16), callbacks int);
CREATE TABLE #vt_probe (value int);
CREATE TABLE #vt_report (scenario varchar(100), status varchar(8));
INSERT #vt_control VALUES (NULL, 0);

BEGIN TRY
	EXEC sys.sp_executesql N'CREATE PROC [test].[vt_logger]
		@message nvarchar(max) = NULL, @data nvarchar(max) = NULL, @severity nvarchar(8) = N''debug'',
		@p1 sql_variant = NULL, @p2 sql_variant = NULL, @p3 sql_variant = NULL, @p4 sql_variant = NULL,
		@p1_str nvarchar(max) = NULL, @p2_str nvarchar(max) = NULL,
		@p3_str nvarchar(max) = NULL, @p4_str nvarchar(max) = NULL,
		@proc_id int = NULL, @rowcount int = NULL
	AS
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM #vt_control WHERE
		(logger_failure = ''start'' AND @message LIKE N''Start exec%'')
		OR (logger_failure = ''completed'' AND @message LIKE N''Completed exec%''))
		THROW 51072, ''vt intentional logger failure'', 1;
	INSERT #vt_log VALUES (@message, COALESCE(@data, @p2_str), @severity);';
	EXEC sys.sp_executesql N'CREATE PROC [tests].[test.run@vt_vector]
		@number int = 7, @text nvarchar(max) = N''default'', @mode nvarchar(32) = N''pass''
	AS
	SET NOCOUNT ON;
	INSERT #vt_exec VALUES (@number, @text, @mode);
	IF @mode = N''fail'' BEGIN
		DECLARE @failure int = test.fail(N''vt assertion failure'');
	END;
	IF @mode = N''error'' THROW 51071, ''vt unexpected error'', 1;
	IF @mode = N''rollback'' BEGIN
		BEGIN TRAN; INSERT #vt_probe VALUES (1); ROLLBACK;
	END;
	IF @mode = N''open'' BEGIN
		BEGIN TRAN; INSERT #vt_probe VALUES (1);
	END;
	IF @mode = N''return'' RETURN 13;';
	EXEC sys.sp_executesql N'CREATE PROC [tests].[test.run@vt_static] AS
		EXEC [tests].[test.run@vt_vector] @number = 99;';
	EXEC sys.sp_executesql N'CREATE PROC [tests].[test.run@vt_required] @number int AS
		EXEC [tests].[test.run@vt_vector] @number = @number;';
	EXEC sys.sp_executesql N'CREATE PROC [tests].[test.run@vt_metadata] @number int AS
		EXEC [tests].[test.run@vt_vector] @number = @number;';

	-- Missing tables must be checked before invalid registration inputs.
	EXEC test.set_scope N'session';
	EXEC test.vector NULL, NULL;
	EXEC test.reset;
	EXEC test.run @test_names = N'[tests].[test.run@vt_static]', @log_proc_name = N'test.vt_logger';
	IF (SELECT COUNT(*) FROM #vt_exec) <> 1
		THROW 51091, 'Missing-table fallback did not execute one static call.', 1;
	INSERT #vt_report VALUES ('missing session table warns/skips and static fallback', 'PASS');

	CREATE TABLE #test_vectors (
		procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
	);

	DECLARE @cases nvarchar(max) = N'[
	 {"name":"global default and no store merge","vectors":["1","2"],"exec":2},
	 {"name":"session selection and no store merge","scope":"session","vectors":["10","20"],"exec":2},
	 {"name":"duplicate vectors are separate calls","vectors":["1","1","2"],"exec":3},
	 {"name":"unregistered static fallback","vectors":[],"exec":1,"static":1},
	 {"name":"mixed vector and static reporting","vectors":["1","2"],"mixed":1,"exec":3},
	 {"name":"SQL defaults with named arguments","vectors":["@text = N''provided''"],"exec":1},
	 {"name":"apostrophes and commas remain literal","vectors":["1,N''O''''Brien, Jr.''"],"exec":1},
	 {"name":"SQL NULL argument text","vectors":["NULL,NULL"],"exec":1},
	 {"name":"invalid SQL is a caught case error","vectors":["1,"],"exec":0,"code":70000,"errors":1},
	 {"name":"conversion error is not an assertion","vectors":["N''not-int''"],"exec":0,"code":70000,"errors":1},
	 {"name":"unknown named argument is native error","vectors":["@unknown = 1"],"exec":0,"code":70000,"errors":1},
	 {"name":"required parameter static fallback","target":"required","vectors":[],"exec":0,"code":70000,"static":1,"errors":1},
	 {"name":"required parameter supplied by vector","target":"required","vectors":["42"],"exec":1},
	 {"name":"assertion classification","vectors":["1,N''x'',N''fail''"],"exec":1,"code":70000,"failed":1},
	 {"name":"unexpected error classification","vectors":["1,N''x'',N''error''"],"exec":1,"code":70000,"errors":1},
	 {"name":"failure limit one includes completion","vectors":["1,N''x'',N''fail''","2,N''x'',N''fail''","3,N''x'',N''fail''"],"limit":1,"exec":1,"code":70000,"failed":1},
	 {"name":"failure limit two includes completions","vectors":["1,N''x'',N''fail''","2,N''x'',N''fail''","3,N''x'',N''fail''"],"limit":2,"exec":2,"code":70000,"failed":2},
	 {"name":"zero limit preserves legacy behavior","vectors":["1,N''x'',N''fail''","2,N''x'',N''fail''"],"limit":0,"exec":2,"code":70000,"failed":2},
	 {"name":"negative limit preserves legacy behavior","vectors":["1,N''x'',N''fail''","2,N''x'',N''fail''"],"limit":-1,"exec":2,"code":70000,"failed":2},
	 {"name":"callback reset does not change snapshot","vectors":["1","2"],"callback":"EXEC test.reset;","exec":2},
	 {"name":"callback scope switch does not change snapshot","vectors":["1","2"],"callback":"EXEC test.set_scope N''session''; EXEC test.reset;","exec":2},
	 {"name":"callback append does not add active cases","vectors":["1","2"],"callback":"EXEC test.vector N''[tests].[test.run@vt_vector]'',N''9'';","exec":2},
	 {"name":"callback error aborts before invocation","vectors":["1"],"callback":"THROW 51073,''vt callback failure'',1;","exec":0,"code":51073,"summary":0,"completed":0,"started":0},
	 {"name":"callback error rolls back transaction","vectors":["1"],"callback":"BEGIN TRAN; INSERT #vt_probe VALUES (1); THROW 51073,''vt callback failure'',1;","exec":0,"code":51073,"summary":0,"completed":0,"started":0},
	 {"name":"start logger error is not a case error","vectors":["1"],"logger":"start","exec":0,"code":51072,"summary":0,"completed":0,"started":0},
	 {"name":"completion logger error aborts framework","vectors":["1"],"logger":"completed","exec":1,"code":51072,"summary":0,"completed":0,"started":1},
	 {"name":"duplicate selection preserves attempt timing","vectors":["1","2"],"duplicate":1,"exec":3,"code":50000,"summary":0,"completed":2,"started":3},
	 {"name":"duplicate failing selection is not another case","vectors":["1,N''x'',N''fail''","2,N''x'',N''fail''"],"duplicate":1,"exec":3,"code":50000,"summary":0,"completed":2,"started":3},
	 {"name":"test-owned rollback preserves frozen cases","vectors":["1,N''x'',N''rollback''","2,N''x'',N''rollback''"],"exec":2},
	 {"name":"unbalanced transaction is caught and rolled back","vectors":["1,N''x'',N''open''"],"exec":1,"code":70000,"errors":1},
	 {"name":"nonzero return is successful","vectors":["1,N''x'',N''return''"],"exec":1},
	 {"name":"metadata removal keeps recorded error rows","target":"metadata","vectors":["1","2"],"callback":"DROP PROC IF EXISTS [tests].[test.run@vt_metadata];","exec":0,"code":70000,"errors":2}
	]';
	DECLARE @i bigint = 0, @n bigint = (SELECT COUNT_BIG(*) FROM OPENJSON(@cases)),
		@name varchar(100), @scope nvarchar(7), @vectors nvarchar(max), @target nvarchar(16),
		@procedure nvarchar(max), @names nvarchar(max), @callback nvarchar(max), @logger varchar(16),
		@limit int, @expected_exec int, @expected_code int, @expected_errors int, @expected_failed int,
		@expected_summary int, @expected_started int, @expected_completed int,
		@mixed bit, @duplicate bit, @static bit, @code int, @j bigint, @vector_count bigint,
		@parameters nvarchar(max), @summary nvarchar(max), @started int, @completed int;
	WHILE @i < @n
	BEGIN
		EXEC test.set_scope N'global'; EXEC test.reset;
		EXEC test.set_scope N'session'; EXEC test.reset;
		TRUNCATE TABLE #vt_exec; TRUNCATE TABLE #vt_log; TRUNCATE TABLE #vt_probe;
		SELECT @name = name, @scope = scope, @vectors = vectors, @target = COALESCE(target, N'vector'),
			@callback = callback, @logger = logger, @limit = limit_failed,
			@expected_exec = executions, @expected_code = ISNULL(code, 0),
			@expected_errors = ISNULL(errors, 0), @expected_failed = ISNULL(failed, 0),
			@expected_summary = ISNULL(summary, 1), @expected_started = started,
			@expected_completed = completed, @mixed = ISNULL(mixed, 0),
			@duplicate = ISNULL(duplicate, 0), @static = ISNULL(static, 0)
		FROM OPENJSON(@cases, CONCAT('$[', @i, ']'))
		WITH (name varchar(100), scope nvarchar(7), vectors nvarchar(max) AS JSON, target nvarchar(16),
			callback nvarchar(max), logger varchar(16), limit_failed int '$.limit',
			executions int '$.exec', code int, errors int, failed int, summary int,
			started int, completed int, mixed bit, duplicate bit, static bit);
		SET @procedure = CONCAT(N'[tests].[test.run@vt_', @target, N']');
		SET @names = @procedure;
		IF @mixed = 1 SET @names += N'|[tests].[test.run@vt_static]';
		IF @duplicate = 1 SET @names += N'|' + @procedure + N'|' + @procedure;
		IF @scope IS NULL
			EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = NULL;
		ELSE EXEC test.set_scope @scope;
		UPDATE #vt_control SET logger_failure = @logger, callbacks = 0;
		SET @j = 0;
		SET @vector_count = (SELECT COUNT_BIG(*) FROM OPENJSON(@vectors));
		WHILE @j < @vector_count
		BEGIN
			SELECT @parameters = value FROM OPENJSON(@vectors) WHERE CONVERT(bigint, [key]) = @j;
			EXEC test.vector @procedure, @parameters;
			SET @j += 1;
		END;
		-- The other store must never supply or append cases.
		IF @scope = N'session'
			INSERT [test].[test_vectors] (procedure_name, parameters) VALUES (@procedure, '98');
		ELSE INSERT #test_vectors VALUES (@procedure, '98');
		SET @callback = N'UPDATE #vt_control SET callbacks += 1; ' + COALESCE(@callback, N'');
		SET @code = 0;
		BEGIN TRY
			EXEC test.run @test_names = @names, @limit_failed = @limit,
				@before_callback = @callback, @log_proc_name = N'test.vt_logger';
		END TRY
		BEGIN CATCH
			SET @code = ERROR_NUMBER();
		END CATCH;
		IF @@TRANCOUNT > 0 THROW 51091, 'Vector runner leaked a transaction.', 1;
		IF EXISTS (SELECT 1 FROM #vt_probe) THROW 51091, 'Vector runner did not roll back probe data.', 1;
		IF @code <> @expected_code OR (SELECT COUNT(*) FROM #vt_exec) <> @expected_exec
		BEGIN
			DECLARE @diagnostic nvarchar(2048) = CONCAT(@name, N': code=', @code,
				N'; fixture calls=', (SELECT COUNT(*) FROM #vt_exec), N'; expected ',
				@expected_code, N' and ', @expected_exec);
			THROW 51091, @diagnostic, 1;
		END;
		IF EXISTS (SELECT 1 FROM #vt_exec WHERE number = 98)
			THROW 51091, 'The runner merged scopes or fell back to the other store.', 1;
		SELECT @started = COUNT(*) FROM #vt_log WHERE message LIKE 'Start exec%';
		SELECT @completed = COUNT(*) FROM #vt_log WHERE message LIKE 'Completed exec%';
		SET @summary = NULL;
		SELECT @summary = message FROM #vt_log WHERE severity = 'Info';
		IF @started <> COALESCE(@expected_started,
			IIF(@static = 1, 0, IIF(@expected_failed + @expected_errors > @expected_exec,
				@expected_failed + @expected_errors, @expected_exec) - CONVERT(int, @mixed)))
			OR @completed <> COALESCE(@expected_completed, @started)
			THROW 51091, 'Vector start/completion logging count mismatch.', 1;
		IF (@expected_summary = 0 AND @summary IS NOT NULL)
			OR (@expected_summary = 1 AND @summary IS NULL)
			THROW 51091, 'Vector framework abort or summary behavior mismatch.', 1;
		IF @expected_summary = 1 AND @static = 0
			AND @summary NOT LIKE CONCAT('%failed: ', @expected_failed, ', errors: ', @expected_errors)
			THROW 51091, 'Vector failure classification or summary mismatch.', 1;
		IF @name = 'duplicate vectors are separate calls' AND (SELECT COUNT(*) FROM #vt_exec WHERE number = 1) <> 2
			THROW 51091, 'Identical vectors were deduplicated.', 1;
		IF @name = 'SQL defaults with named arguments' AND NOT EXISTS
			(SELECT 1 FROM #vt_exec WHERE number = 7 AND text = 'provided')
			THROW 51091, 'SQL parameter defaults were not preserved.', 1;
		IF @name = 'apostrophes and commas remain literal' AND NOT EXISTS
			(SELECT 1 FROM #vt_exec WHERE text = 'O''Brien, Jr.')
			THROW 51091, 'The vector argument text was split or re-escaped.', 1;
		IF @name = 'SQL NULL argument text' AND NOT EXISTS
			(SELECT 1 FROM #vt_exec WHERE number IS NULL AND text IS NULL)
			THROW 51091, 'SQL NULL arguments were converted to text.', 1;
		IF @name = 'callback scope switch does not change snapshot'
			AND CONVERT(nvarchar(7), SESSION_CONTEXT(N'ttest:vectors:scope')) <> N'session'
			THROW 51091, 'The runner incorrectly restored a callback scope change.', 1;
		IF @expected_summary = 1 AND (SELECT callbacks FROM #vt_control) <> @started + CONVERT(int, @static) + CONVERT(int, @mixed)
			THROW 51091, 'The before callback was not run exactly once per case.', 1;
		INSERT #vt_report VALUES (@name, 'PASS');
		SET @i += 1;
	END;

	EXEC test.set_scope N'global'; EXEC test.reset;
	TRUNCATE TABLE #vt_exec; TRUNCATE TABLE #vt_log;
	UPDATE #vt_control SET logger_failure = NULL;
	DECLARE @long_text nvarchar(max) = REPLICATE(CONVERT(nvarchar(max), N'x'), 7000)
		+ NCHAR(381) + N'O''Brien, Jr.' + NCHAR(10);
	SET @parameters = N'5,N''' + REPLACE(@long_text, N'''', N'''''') + N'''';
	EXEC test.vector N'[tests].[test.run@vt_vector]', @parameters;
	EXEC test.vector N'[tests].[test.run@vt_vector]', @parameters;
	EXEC test.run @test_names = N'[tests].[test.run@vt_vector]', @log_proc_name = N'test.vt_logger';
	DECLARE @expected_call nvarchar(max) = N'EXEC [tests].[test.run@vt_vector] ' + @parameters + N';';
	IF (SELECT COUNT(*) FROM #vt_exec WHERE CONVERT(nvarchar(max), text) COLLATE Latin1_General_100_BIN2
			= @long_text COLLATE Latin1_General_100_BIN2 AND DATALENGTH(CONVERT(nvarchar(max), text)) = DATALENGTH(@long_text)) <> 2
		OR (SELECT COUNT(*) FROM #vt_log WHERE message LIKE '%exec source=explicit%'
			AND CONVERT(nvarchar(max), data) COLLATE Latin1_General_100_BIN2 = @expected_call COLLATE Latin1_General_100_BIN2
			AND DATALENGTH(CONVERT(nvarchar(max), data)) = DATALENGTH(@expected_call)) <> 4
		THROW 51091, 'Long/Unicode argument or complete log data was truncated.', 1;
	INSERT #vt_report VALUES ('long Unicode calls remain exact and duplicated', 'PASS');

	DECLARE @invalid nvarchar(max) = N'[
	 "EXEC test.set_scope NULL;",
	 "EXEC test.set_scope N'''';",
	 "EXEC test.set_scope N''GLOBAL'';",
	 "EXEC test.set_scope N''global '';",
	 "EXEC test.set_scope N''session '';",
	 "EXEC test.vector NULL,N''1'';",
	 "EXEC test.vector N''test.run@vt_vector'',N''1'';",
	 "EXEC test.vector N''[tempdb].[tests].[test.run@vt_vector]'',N''1'';",
	 "EXEC test.vector N''[test].[run]'',N''1'';",
	 "EXEC test.vector N''[tests].[vt_missing]'',N''1'';",
	 "EXEC test.vector N''[tests].[test.run@vt_vector]'',NULL;",
	 "EXEC test.vector N''[tests].[test.run@vt_vector]'',N'''';",
	 "EXEC test.vector N''[tests].[test.run@vt_vector]'',N''  '';"
	]';
	SET @i = 0;
	SET @n = (SELECT COUNT_BIG(*) FROM OPENJSON(@invalid));
	WHILE @i < @n
	BEGIN
		SELECT @parameters = value FROM OPENJSON(@invalid) WHERE CONVERT(bigint, [key]) = @i;
		SET @code = 0;
		BEGIN TRY EXEC sys.sp_executesql @parameters; END TRY
		BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;
		IF @code <> 70000 THROW 51091, 'Invalid scope/registration input was accepted.', 1;
		SET @i += 1;
	END;
	SET @parameters = NCHAR(9) + NCHAR(10) + NCHAR(13);
	SET @code = 0;
	BEGIN TRY EXEC test.vector N'[tests].[test.run@vt_vector]', @parameters; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;
	IF @code <> 70000 THROW 51091, 'Whitespace-only vector was accepted.', 1;
	SET @parameters = REPLICATE(CONVERT(nvarchar(max), N'x'), 5000);
	SET @code = 0;
	BEGIN TRY EXEC test.set_scope @parameters; END TRY
	BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;
	IF @code <> 70000 THROW 51091, 'Oversized scope was truncated before validation.', 1;
	INSERT #vt_report VALUES ('scope and registration validation', 'PASS');

	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = N'invalid';
	SET @invalid = N'["EXEC test.vector NULL,NULL;","EXEC test.reset;","EXEC test.run;"]';
	SET @i = 0;
	WHILE @i < 3
	BEGIN
		SELECT @parameters = value FROM OPENJSON(@invalid) WHERE CONVERT(bigint, [key]) = @i;
		SET @code = 0;
		BEGIN TRY EXEC sys.sp_executesql @parameters; END TRY
		BEGIN CATCH SET @code = ERROR_NUMBER(); END CATCH;
		IF @code <> 70000 THROW 51091, 'Invalid manual context silently fell back to a scope.', 1;
		SET @i += 1;
	END;
	INSERT #vt_report VALUES ('invalid manual context is rejected by every storage API', 'PASS');
	EXEC test.set_scope N'global'; EXEC test.reset;
	IF EXISTS (SELECT 1 FROM [test].[test_vectors])
		OR CONVERT(nvarchar(7), SESSION_CONTEXT(N'ttest:vectors:scope')) <> N'global'
		THROW 51091, 'Reset did not clear selected storage while preserving scope.', 1;
	IF NOT EXISTS (SELECT 1 FROM #test_vectors)
		THROW 51091, 'Global reset changed session registrations.', 1;
	INSERT #vt_report VALUES ('reset affects only chosen store and retains scope', 'PASS');

	DROP PROCEDURE [tests].[test.run@vt_required];
	DROP PROCEDURE [tests].[test.run@vt_static];
	DROP PROCEDURE [tests].[test.run@vt_vector];
	DROP PROCEDURE IF EXISTS [tests].[test.run@vt_metadata];
	DROP PROCEDURE [test].[vt_logger];
	DELETE FROM [test].[test_vectors]
	WHERE procedure_name IN ('[tests].[test.run@vt_vector]',
		'[tests].[test.run@vt_required]', '[tests].[test.run@vt_metadata]', '[tests].[power@vectors]');
	INSERT [test].[test_vectors] (procedure_name, parameters)
	SELECT procedure_name, parameters
	FROM OPENJSON(@original_vectors) WITH (procedure_name nvarchar(max), parameters nvarchar(max));
	IF OBJECT_ID(N'[test].[test_vectors]', N'U') IS DISTINCT FROM @global_table_id
		THROW 51091, 'Vector coverage replaced or removed the installed global table.', 1;
	DROP TABLE #test_vectors;
	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
	SELECT scenario, status FROM #vt_report ORDER BY scenario;
	SELECT 'PASSED' AS vector_result, COUNT(*) AS scenario_groups, 0 AS failed_groups FROM #vt_report;
	DROP TABLE #vt_exec; DROP TABLE #vt_log; DROP TABLE #vt_control;
	DROP TABLE #vt_probe; DROP TABLE #vt_report;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;
	DROP PROCEDURE IF EXISTS [tests].[test.run@vt_required];
	DROP PROCEDURE IF EXISTS [tests].[test.run@vt_static];
	DROP PROCEDURE IF EXISTS [tests].[test.run@vt_vector];
	DROP PROCEDURE IF EXISTS [tests].[test.run@vt_metadata];
	DROP PROCEDURE IF EXISTS [test].[vt_logger];
	DELETE FROM [test].[test_vectors]
	WHERE procedure_name IN ('[tests].[test.run@vt_vector]',
		'[tests].[test.run@vt_required]', '[tests].[test.run@vt_metadata]', '[tests].[power@vectors]');
	INSERT [test].[test_vectors] (procedure_name, parameters)
	SELECT procedure_name, parameters
	FROM OPENJSON(@original_vectors) WITH (procedure_name nvarchar(max), parameters nvarchar(max));
	DROP TABLE IF EXISTS #test_vectors;
	DROP TABLE #vt_exec; DROP TABLE #vt_log; DROP TABLE #vt_control;
	DROP TABLE #vt_probe; DROP TABLE #vt_report;
	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
	THROW;
END CATCH;
