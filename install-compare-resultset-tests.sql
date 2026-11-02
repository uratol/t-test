-- Catalog-content comparisons for Fabric Warehouse / SQL Server 2022+.
-- Install T-TEST first, then execute this entire file outside a transaction.
-- Adds 12 tests named [tests].[sys.objects@<counterpart>].
-- The sys.objects@tables comparison is already in the basic package.
-- SYS pairs compare all 12 shared sys.objects columns plus schema_name.
-- INFORMATION_SCHEMA pairs compare equivalent names, kinds, parents and dates.
-- Include NULL properties; shared SYS data types are text, int, datetime and bit.
-- SYS tests exclude MS-shipped objects; INFORMATION_SCHEMA tests use its scope.
-- Empty subsets compare as []; no persistent fixture objects are created.
-- Use an owner/metadata-visible account and avoid concurrent DDL.
-- Tests remain installed and do not depend on the registration temp table.
-- Example: EXEC test.run @test_names = N'[tests].[sys.objects@views]';
SET NOCOUNT ON;

IF @@TRANCOUNT > 0
	THROW 51090, 'Run catalog test registration outside a transaction.', 1;
IF SCHEMA_ID(N'tests') IS NULL OR OBJECT_ID(N'test.run', N'P') IS NULL
	OR OBJECT_ID(N'test.assert_equals', N'FN') IS NULL
	THROW 51090, 'Install the T-TEST framework before running this file.', 1;

DROP TABLE IF EXISTS #tt_sys_objects_cases;
CREATE TABLE #tt_sys_objects_cases (
	case_id int,
	action_name varchar(128),
	objects_filter nvarchar(max),
	objects_projection nvarchar(max),
	counterpart_query nvarchar(max)
);

DECLARE @shared_columns nvarchar(max) =
	N'SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
		o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
		o.type, o.type_desc, o.create_date, o.modify_date,
		o.is_ms_shipped, o.is_published, o.is_schema_published';

INSERT #tt_sys_objects_cases (case_id, action_name, objects_filter, objects_projection, counterpart_query)
SELECT case_id, view_name, objects_filter, @shared_columns,
	N'SELECT ' + @shared_columns + N' FROM sys.'
		+ QUOTENAME(view_name) + N' o WHERE ' + objects_filter
FROM (VALUES
	(1, 'views', N'o.type = N''V'' AND o.is_ms_shipped = 0'),
	(2, 'procedures', N'o.type = N''P'' AND o.is_ms_shipped = 0'),
	(3, 'key_constraints', N'o.type IN (N''PK'', N''UQ'') AND o.is_ms_shipped = 0'),
	(4, 'foreign_keys', N'o.type = N''F'' AND o.is_ms_shipped = 0'),
	(5, 'check_constraints', N'o.type = N''C'' AND o.is_ms_shipped = 0'),
	(6, 'default_constraints', N'o.type = N''D'' AND o.parent_object_id <> 0 AND o.is_ms_shipped = 0')
) v(case_id, view_name, objects_filter);

INSERT #tt_sys_objects_cases (case_id, action_name, objects_filter, objects_projection, counterpart_query)
VALUES
	(7, 'information_schema.tables',
		N'o.type IN (N''U'', N''V'')',
		N'DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name,
			o.name AS object_name, CASE o.type WHEN N''U'' THEN N''BASE TABLE'' ELSE N''VIEW'' END AS table_type',
		N'SELECT TABLE_CATALOG AS catalog_name, TABLE_SCHEMA AS schema_name,
			TABLE_NAME AS object_name, TABLE_TYPE AS table_type
			FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE IN (N''BASE TABLE'', N''VIEW'')'),
	(8, 'information_schema.views',
		N'o.type = N''V''',
		N'DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name',
		N'SELECT TABLE_CATALOG AS catalog_name, TABLE_SCHEMA AS schema_name,
			TABLE_NAME AS object_name FROM INFORMATION_SCHEMA.VIEWS'),
	(9, 'information_schema.routines',
		N'o.type IN (N''P'', N''FN'', N''IF'', N''TF'')',
		N'DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			CASE o.type WHEN N''P'' THEN N''PROCEDURE'' ELSE N''FUNCTION'' END AS routine_type,
			o.create_date, o.modify_date',
		N'SELECT ROUTINE_CATALOG AS catalog_name, ROUTINE_SCHEMA AS schema_name,
			ROUTINE_NAME AS object_name, ROUTINE_TYPE AS routine_type,
			CREATED AS create_date, LAST_ALTERED AS modify_date
			FROM INFORMATION_SCHEMA.ROUTINES
			WHERE ROUTINE_BODY = N''SQL'' AND ROUTINE_TYPE IN (N''PROCEDURE'', N''FUNCTION'')'),
	(10, 'information_schema.table_constraints',
		N'o.type IN (N''C'', N''F'', N''PK'', N''UQ'')',
		N'DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			DB_NAME() AS table_catalog_name, OBJECT_SCHEMA_NAME(o.parent_object_id) AS table_schema_name,
			OBJECT_NAME(o.parent_object_id) AS table_name,
			CASE o.type WHEN N''C'' THEN N''CHECK'' WHEN N''F'' THEN N''FOREIGN KEY''
				WHEN N''PK'' THEN N''PRIMARY KEY'' ELSE N''UNIQUE'' END AS constraint_type',
		N'SELECT CONSTRAINT_CATALOG AS catalog_name, CONSTRAINT_SCHEMA AS schema_name,
			CONSTRAINT_NAME AS object_name, TABLE_CATALOG AS table_catalog_name,
			TABLE_SCHEMA AS table_schema_name, TABLE_NAME AS table_name, CONSTRAINT_TYPE AS constraint_type
			FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
			WHERE CONSTRAINT_TYPE IN (N''CHECK'', N''FOREIGN KEY'', N''PRIMARY KEY'', N''UNIQUE'')'),
	(11, 'information_schema.check_constraints',
		N'o.type = N''C''',
		N'DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name',
		N'SELECT CONSTRAINT_CATALOG AS catalog_name, CONSTRAINT_SCHEMA AS schema_name, CONSTRAINT_NAME AS object_name
			FROM INFORMATION_SCHEMA.CHECK_CONSTRAINTS'),
	(12, 'information_schema.referential_constraints',
		N'o.type = N''F''',
		N'DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name',
		N'SELECT CONSTRAINT_CATALOG AS catalog_name, CONSTRAINT_SCHEMA AS schema_name, CONSTRAINT_NAME AS object_name
			FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS');

DECLARE @template nvarchar(max) = N'CREATE OR ALTER PROC [tests].{{procedure}}
AS
BEGIN
	SET NOCOUNT ON;
	PRINT N''Compare filtered sys.objects and catalog-view rows.'';
	PRINT N''Expect: equivalent columns match, including NULLs.'';

	DECLARE @expected nvarchar(max), @actual nvarchar(max), @result nvarchar(max);

	-- Arrange
	SET @expected = (
		SELECT {{projection}}
		FROM sys.objects o
		WHERE {{filter}}
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2
		FOR JSON PATH, INCLUDE_NULL_VALUES
	);

	-- Act
	SET @actual = (
		SELECT r.*
		FROM ({{counterpart}}) r
		ORDER BY r.schema_name COLLATE Latin1_General_100_BIN2,
			r.object_name COLLATE Latin1_General_100_BIN2
		FOR JSON PATH, INCLUDE_NULL_VALUES
	);

	-- Assert
	SET @result = test.assert_equals(
		N''sys.objects subset must match all equivalent {{label}} columns'',
		@expected, @actual);
END;';

DECLARE @case_id int = 1, @case_count int = (SELECT COUNT(*) FROM #tt_sys_objects_cases),
	@expected_count int = 12, @action_name nvarchar(128), @procedure_name nvarchar(128),
	@filter nvarchar(max), @projection nvarchar(max), @counterpart nvarchar(max), @sql nvarchar(max),
	@test_names nvarchar(max);

BEGIN TRY
	IF @case_count <> @expected_count
		OR (SELECT COUNT(DISTINCT action_name) FROM #tt_sys_objects_cases) <> @expected_count
		THROW 51090, 'Incomplete or duplicate catalog comparison definitions.', 1;

	WHILE @case_id <= @case_count
	BEGIN
		SELECT @action_name = action_name, @filter = objects_filter, @projection = objects_projection,
			@counterpart = counterpart_query
		FROM #tt_sys_objects_cases WHERE case_id = @case_id;
		SET @procedure_name = N'sys.objects@' + @action_name;
		SET @sql = REPLACE(@template, N'{{procedure}}', QUOTENAME(@procedure_name));
		SET @sql = REPLACE(@sql, N'{{filter}}', @filter);
		SET @sql = REPLACE(@sql, N'{{projection}}', @projection);
		SET @sql = REPLACE(@sql, N'{{counterpart}}', @counterpart);
		SET @sql = REPLACE(@sql, N'{{label}}',
			IIF(@action_name LIKE N'information_schema.%', @action_name, N'sys.' + @action_name));
		EXEC sys.sp_executesql @sql;
		SET @case_id += 1;
	END;

	IF EXISTS (SELECT 1 FROM #tt_sys_objects_cases
		WHERE OBJECT_ID(N'[tests].' + QUOTENAME(N'sys.objects@' + action_name), N'P') IS NULL)
		THROW 51090, 'Catalog test registration is incomplete.', 1;
	SELECT @test_names = STRING_AGG(
		CONVERT(nvarchar(max), N'[tests].' + QUOTENAME(N'sys.objects@' + action_name)), N'|')
	FROM #tt_sys_objects_cases;
END TRY
BEGIN CATCH
	DROP TABLE #tt_sys_objects_cases;
	THROW;
END CATCH;

DROP TABLE #tt_sys_objects_cases;
EXEC test.run @test_names = @test_names;
