-- SQL Server 2022+ API compatibility and named-argument checks.
-- Run install.sql first, outside a transaction and without caller registration tables.
SET NOCOUNT ON;
IF @@TRANCOUNT > 0
    THROW 51090, 'Run api-tests.sql outside a transaction.', 1;
IF OBJECT_ID(N'tempdb..#test_vectors') IS NOT NULL
    OR OBJECT_ID(N'tempdb..#test_dimension_values') IS NOT NULL
    OR OBJECT_ID(N'tempdb..#api_callbacks') IS NOT NULL
    THROW 51090, 'API checks require no caller fixture tables.', 1;

DECLARE @signature nvarchar(max), @formatted nvarchar(max),
    @previous_scope sql_variant = SESSION_CONTEXT(N'ttest:vectors:scope');
DECLARE @parameters TABLE (
    object_name sysname, position int, name sysname, type_name sysname,
    max_length smallint, is_output bit
);
INSERT @parameters VALUES
    (N'run', 5, N'@max_failures', N'int', 4, 0),
    (N'run', 6, N'@before_each_sql', N'nvarchar', -1, 0),
    (N'vector', 2, N'@arguments_sql', N'nvarchar', -1, 0),
    (N'dimension', 3, N'@values_json', N'nvarchar', -1, 0),
    (N'assert_schema_signature', 2, N'@expected_schema_signature', N'nvarchar', -1, 0),
    (N'assert_query_schemas_equal', 2, N'@expected_query', N'nvarchar', -1, 0),
    (N'assert_query_schemas_equal', 3, N'@actual_query', N'nvarchar', -1, 0),
    (N'get_query_schema', 3, N'@schema_signature', N'nvarchar', -1, 1),
    (N'format_message', 1, N'@message', N'nvarchar', -1, 0),
    (N'set_registration_scope', 1, N'@scope', N'nvarchar', -1, 0),
    (N'clear_registrations', 1, N'@test_name', N'nvarchar', -1, 0),
    (N'is_float_equal', 3, N'@tolerance', N'float', 8, 0);

-- Arrange
--N/A

-- Act
SELECT @signature = STRING_AGG(CONVERT(nvarchar(max), expected.object_name), N', ')
FROM @parameters expected
LEFT JOIN sys.parameters actual
    ON actual.object_id = OBJECT_ID(QUOTENAME(N'test') + N'.' + QUOTENAME(expected.object_name))
    AND actual.parameter_id = expected.position
WHERE actual.name IS NULL OR actual.name COLLATE Latin1_General_100_BIN2 <> expected.name COLLATE Latin1_General_100_BIN2
    OR TYPE_NAME(actual.user_type_id) <> expected.type_name
    OR actual.max_length <> expected.max_length OR actual.is_output <> expected.is_output;

-- Assert
IF @signature IS NOT NULL
    THROW 51091, 'Renamed API parameters changed position, type or OUTPUT semantics.', 1;
IF OBJECT_ID(N'test.set_scope') IS NOT NULL OR OBJECT_ID(N'test.reset') IS NOT NULL
    OR OBJECT_ID(N'test.is_float_equals') IS NOT NULL
    OR OBJECT_ID(N'test.assert_schema') IS NOT NULL
    OR OBJECT_ID(N'test.assert_schema_equals') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.assert_schema_equals]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.assert_query_schemas_equal]', N'P') IS NULL
    THROW 51091, 'Retired API names remain installed.', 1;
IF (SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID(N'test')) <> 17
    OR (SELECT COUNT(*) FROM sys.objects WHERE schema_id = SCHEMA_ID(N'test') AND type = 'FN') <> 9
    OR (SELECT COUNT(*) FROM sys.views WHERE schema_id = SCHEMA_ID(N'test')) <> 2
    THROW 51091, 'The public API module inventory changed.', 1;
IF test.is_equal(N'01', N'1') IS DISTINCT FROM 1
    OR test.is_equals(N'01', N'1') IS DISTINCT FROM 1
    OR test.is_float_equal(1, 1.125, 0.125) IS DISTINCT FROM 1
    OR test.is_float_equal(1, 1.125, 0.1) IS DISTINCT FROM 0
    THROW 51091, 'Canonical predicates or the equality compatibility alias changed behavior.', 1;

-- Arrange
SET @signature = NULL;

-- Act
EXEC test.get_query_schema @message = N'Named OUTPUT', @query = N'SELECT 1 AS id',
    @schema_signature = @signature OUTPUT;
EXEC test.assert_schema_signature @message = N'Named signature',
    @expected_schema_signature = N'[id] int', @actual_query = N'SELECT 99 AS id';
EXEC test.assert_query_schemas_equal @message = N'Named reference query',
    @expected_query = N'SELECT 1 AS id', @actual_query = N'SELECT 99 AS id';
SET @formatted = test.format_message(N'Value %1', 42, DEFAULT, DEFAULT, DEFAULT);

-- Assert
IF @signature IS DISTINCT FROM N'[id] int' OR @formatted IS DISTINCT FROM N'Value 42'
    THROW 51091, 'Schema/formatter API results changed.', 1;

-- Arrange
CREATE TABLE #test_vectors (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);
CREATE TABLE #test_dimension_values (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);
CREATE TABLE #api_callbacks (marker int);
BEGIN TRY
    -- Act
    EXEC test.set_registration_scope @scope = N'session';
    EXEC test.vector @test_name = N'[tests].[replicate@dimensions]', @arguments_sql = N'2,N''ab''';
    EXEC test.dimension @test_name = N'[tests].[replicate@dimensions]',
        @parameter_name = N'@number', @values_json = N'[1,2]';
    EXEC test.run @test_names = N'[tests].[replicate@dimensions]',
        @max_failures = 1, @before_each_sql = N'INSERT #api_callbacks VALUES (1);';

    -- Assert
    IF (SELECT COUNT(*) FROM #api_callbacks) <> 3
        OR (SELECT COUNT(*) FROM #test_vectors) <> 1
        OR (SELECT COUNT(*) FROM #test_dimension_values) <> 2
        THROW 51091, 'Named registration/runner arguments changed invocation behavior.', 1;

    -- Arrange
    --N/A

    -- Act
    EXEC test.clear_registrations @test_name = N'[tests].[replicate@dimensions]';

    -- Assert
    IF EXISTS (SELECT 1 FROM #test_vectors) OR EXISTS (SELECT 1 FROM #test_dimension_values)
        OR CONVERT(nvarchar(7), SESSION_CONTEXT(N'ttest:vectors:scope')) IS DISTINCT FROM N'session'
        THROW 51091, 'Named cleanup did not clear cases or changed registration scope.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
    DROP TABLE #api_callbacks, #test_dimension_values, #test_vectors;
    THROW;
END CATCH;
EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_scope;
DROP TABLE #api_callbacks, #test_dimension_values, #test_vectors;
PRINT N'API_PASS: renamed signatures, named calls, compatibility alias and registration behavior.';
