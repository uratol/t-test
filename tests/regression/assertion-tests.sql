-- SQL Server 2022+ assertion contracts, including failure paths and probe cleanup.
-- Run install.sql first, then this entire file outside a transaction.
-- Expected errors are caught and checked independently of framework assertions.
SET NOCOUNT ON;
IF @@TRANCOUNT > 0
    THROW 51090, 'Run assertion-tests.sql outside a transaction.', 1;
SET XACT_ABORT OFF;
IF OBJECT_ID(N'test.assert_resultset_equals', N'P') IS NULL
    OR OBJECT_ID(N'test.get_query_schema', N'P') IS NULL
    OR OBJECT_ID(N'test.assert_schema_signature', N'P') IS NULL
    OR OBJECT_ID(N'test.assert_query_schemas_equal', N'P') IS NULL
    THROW 51090, 'Install the framework before running assertion checks.', 1;

DECLARE @cases TABLE (
    id int IDENTITY(1,1), name nvarchar(100), api char(1),
    expected nvarchar(max), actual nvarchar(max),
    error_number int, error_pattern nvarchar(300)
);
DECLARE @probes TABLE (object_id int);
DECLARE @i int = 1, @count int, @name nvarchar(100), @api char(1),
    @expected nvarchar(max), @actual nvarchar(max), @schema nvarchar(max),
    @expected_error int, @expected_pattern nvarchar(300),
    @error int, @error_message nvarchar(max), @failure nvarchar(2048),
    @whitespace nvarchar(4) = N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13),
    @long_query nvarchar(max);

-- D: result data, Q: query schemas, S: explicit schema, G: metadata reader.
INSERT @cases (name, api, expected, actual, error_number, error_pattern) VALUES
    (N'empty data', 'D', N'SELECT 1 AS value WHERE 1 = 0', N'SELECT 2 AS value WHERE 1 = 0', 0, NULL),
    (N'property ordering', 'D', N'SELECT 1 AS id, N''text'' AS value', N'SELECT N''text'' AS value, 1 AS id', 0, NULL),
    (N'equal NULLs', 'D', N'SELECT CAST(NULL AS int) AS value', N'SELECT CAST(NULL AS int) AS value', 0, NULL),
    (N'trailing semicolon', 'D', N' SELECT 1 AS value; ', N'SELECT 1 AS value', 0, NULL),
    (N'line comment', 'D', N'SELECT 1 AS value -- comment', N'SELECT 1 AS value', 0, NULL),
    (N'different values', 'D', N'SELECT 1 AS value', N'SELECT 2 AS value', 70001, N'%Unit-test fail: different values%'),
    (N'different row counts', 'D', N'SELECT 1 AS value',
        N'SELECT 1 AS value FROM sys.objects WHERE object_id IN (OBJECT_ID(N''test.run''), OBJECT_ID(N''test.clear_registrations''))', 70001, N'%Unit-test fail:%'),
    (N'row ordering', 'D', N'SELECT object_id FROM sys.objects ORDER BY object_id',
        N'SELECT object_id FROM sys.objects ORDER BY object_id DESC', 70001, N'%Unit-test fail:%'),
    (N'row association', 'D', N'SELECT id, value FROM (VALUES (1, N''a''), (2, N''b'')) v(id, value) ORDER BY id',
        N'SELECT id, value FROM (VALUES (1, N''b''), (2, N''a'')) v(id, value) ORDER BY id', 70001, N'%Unit-test fail:%'),
    (N'NULL versus absent property', 'D', N'SELECT 1 AS id, CAST(NULL AS int) AS value', N'SELECT 1 AS id', 70001, N'%Unit-test fail:%'),
    (N'NULL versus value', 'D', N'SELECT CAST(NULL AS int) AS value', N'SELECT 0 AS value', 70001, N'%Unit-test fail:%'),
    (N'empty versus nonempty data', 'D', N'SELECT 1 AS value WHERE 1 = 0', N'SELECT 1 AS value', 70001, N'%Unit-test fail:%'),
    (N'JSON number versus string', 'D', N'SELECT 1 AS value', N'SELECT N''1'' AS value', 70001, N'%Unit-test fail:%'),
    (N'expected NULL query', 'D', NULL, N'SELECT 1 AS value', 70001, N'%expected query must not be NULL or empty.%'),
    (N'expected empty query', 'D', N'', N'SELECT 1 AS value', 70001, N'%expected query must not be NULL or empty.%'),
    (N'expected semicolon only', 'D', N';', N'SELECT 1 AS value', 70001, N'%expected query must not be NULL or empty.%'),
    (N'actual NULL query', 'D', N'SELECT 1 AS value', NULL, 70001, N'%actual query must not be NULL or empty.%'),
    (N'actual empty query', 'D', N'SELECT 1 AS value', N'', 70001, N'%actual query must not be NULL or empty.%'),
    (N'actual semicolon only', 'D', N'SELECT 1 AS value', N';', 70001, N'%actual query must not be NULL or empty.%'),
    (N'validate inputs before execution', 'D', N'SELECT ttest_missing_column FROM sys.objects', NULL, 70001, N'%actual query must not be NULL or empty.%'),
    (N'expected query error propagates', 'D', N'SELECT ttest_missing_column FROM sys.objects', N'SELECT 1 AS value', 207, N'%ttest_missing_column%'),
    (N'actual query error propagates', 'D', N'SELECT 1 AS value', N'SELECT ttest_missing_column FROM sys.objects', 207, N'%ttest_missing_column%'),
    (N'data conversion error propagates', 'D', N'SELECT 1 AS value', N'SELECT CONVERT(int, N''not an integer'') AS value', 245, N'%not an integer%'),
    (N'empty versus populated schema', 'Q', N'SELECT 1 AS id WHERE 1 = 0', N'SELECT 99 AS id', 0, NULL),
    (N'schema does not execute values', 'Q', N'SELECT 1 AS id', N'SELECT CONVERT(int, N''not an integer'') AS id', 0, NULL),
    (N'column order', 'Q', N'SELECT 1 AS id, N''a'' AS value', N'SELECT N''a'' AS value, 1 AS id', 70001, N'%schema%'),
    (N'column name case', 'Q', N'SELECT 1 AS id', N'SELECT 1 AS ID', 70001, N'%schema%'),
    (N'column count', 'Q', N'SELECT 1 AS id', N'SELECT 1 AS id, 2 AS extra', 70001, N'%schema%'),
    (N'base SQL type', 'Q', N'SELECT CAST(1 AS int) AS id', N'SELECT CAST(1 AS bigint) AS id', 70001, N'%schema%'),
    (N'varchar length', 'Q', N'SELECT CAST(NULL AS varchar(7)) AS value', N'SELECT CAST(NULL AS varchar(8)) AS value', 70001, N'%schema%'),
    (N'nvarchar length', 'Q', N'SELECT CAST(NULL AS nvarchar(7)) AS value', N'SELECT CAST(NULL AS nvarchar(8)) AS value', 70001, N'%schema%'),
    (N'MAX length', 'Q', N'SELECT CAST(NULL AS varchar(max)) AS value', N'SELECT CAST(NULL AS varchar(8000)) AS value', 70001, N'%schema%'),
    (N'decimal precision', 'Q', N'SELECT CAST(NULL AS decimal(18,2)) AS value', N'SELECT CAST(NULL AS decimal(19,2)) AS value', 70001, N'%schema%'),
    (N'decimal scale', 'Q', N'SELECT CAST(NULL AS decimal(18,2)) AS value', N'SELECT CAST(NULL AS decimal(18,3)) AS value', 70001, N'%schema%'),
    (N'temporal scale', 'Q', N'SELECT CAST(NULL AS datetime2(3)) AS value', N'SELECT CAST(NULL AS datetime2(7)) AS value', 70001, N'%schema%'),
    (N'expected NULL schema query', 'Q', NULL, N'SELECT 1 AS id', 70001, N'%expected query: query must not be NULL or empty.%'),
    (N'actual NULL schema query', 'Q', N'SELECT 1 AS id', NULL, 70001, N'%actual query: query must not be NULL or empty.%'),
    (N'expected schema query error', 'Q', N'SELECT ttest_missing_column FROM sys.objects', N'SELECT 1 AS id', 207, N'%ttest_missing_column%'),
    (N'actual schema query error', 'Q', N'SELECT 1 AS id', N'SELECT ttest_missing_column FROM sys.objects', 207, N'%ttest_missing_column%'),
    (N'explicit signature', 'S', N'[id] int, [text] nvarchar(7)', N'SELECT 1 AS id, CAST(NULL AS nvarchar(7)) AS text', 0, NULL),
    (N'explicit signature is exact', 'S', N'[id] int ', N'SELECT 1 AS id', 70001, N'%schema%'),
    (N'NULL signature', 'S', NULL, N'SELECT 1 AS id', 70001, N'%expected schema must not be NULL or empty.%'),
    (N'empty signature', 'S', N'', N'SELECT 1 AS id', 70001, N'%expected schema must not be NULL or empty.%'),
    (N'explicit schema actual NULL', 'S', N'[id] int', NULL, 70001, N'%actual query: query must not be NULL or empty.%'),
    (N'metadata output', 'G', N'[id] int', N'SELECT 1 AS id', 0, NULL),
    (N'quoted column name', 'G', N'[odd]]name] int', N'SELECT 1 AS [odd]]name]', 0, NULL),
    (N'CTE signature', 'G', N'[id] int', N';WITH p AS (SELECT 1 AS id) SELECT id FROM p;', 0, NULL),
    (N'UNION signature', 'G', N'[id] int', N'SELECT 1 AS id UNION ALL SELECT 2 AS id', 0, NULL),
    (N'metadata NULL query', 'G', NULL, NULL, 70001, N'%query must not be NULL or empty.%'),
    (N'metadata empty query', 'G', NULL, N'', 70001, N'%query must not be NULL or empty.%'),
    (N'metadata semicolon only', 'G', NULL, N';', 70001, N'%query must not be NULL or empty.%'),
    (N'invalid SQL cleanup', 'G', NULL, N'SELECT FROM sys.objects', 156, N'%FROM%'),
    (N'duplicate column cleanup', 'G', NULL, N'SELECT 1 AS id, 2 AS id', 4506, N'%id%'),
    (N'view ORDER BY restrictions', 'G', NULL, N'SELECT object_id FROM sys.objects ORDER BY object_id', 1033, N'%ORDER BY%');

INSERT @cases (name, api, expected, actual, error_number, error_pattern) VALUES
    (N'expected whitespace', 'D', @whitespace, N'SELECT 1 AS id', 70001, N'%expected query must not be NULL or empty.%'),
    (N'actual whitespace', 'D', N'SELECT 1 AS id', @whitespace, 70001, N'%actual query must not be NULL or empty.%'),
    (N'whitespace signature', 'S', @whitespace, N'SELECT 1 AS id', 70001, N'%expected schema must not be NULL or empty.%'),
    (N'metadata whitespace', 'G', NULL, @whitespace, 70001, N'%query must not be NULL or empty.%'),
    (N'query whitespace and semicolons', 'G', N'[id] int', @whitespace + N';SELECT 1 AS id;' + @whitespace, 0, NULL);

SET @long_query = N'SELECT REPLICATE(CAST(N''x'' AS nvarchar(max)), 6000) AS value';
INSERT @cases (name, api, expected, actual, error_number, error_pattern) VALUES
    (N'long equal data', 'D', @long_query, @long_query, 0, NULL),
    (N'long data tail mismatch', 'D', @long_query,
        N'SELECT REPLICATE(CAST(N''x'' AS nvarchar(max)), 6000) + N''y'' AS value', 70001, N'%Unit-test fail:%'),
    (N'all formatted SQL types', 'G',
        N'[v] varchar(7), [vmax] varchar(max), [c] char(3), [b] binary(2), [vb] varbinary(8), [vbmax] varbinary(max), '
        + N'[n] nvarchar(7), [nmax] nvarchar(max), [nc] nchar(3), [amount] decimal(18,2), [quantity] numeric(12,4), '
        + N'[stamp] datetime2(3), [zone] datetimeoffset(5), [clock] time(7)',
        N'SELECT CAST(NULL AS varchar(7)) AS v, CAST(NULL AS varchar(max)) AS vmax,
            CAST(NULL AS char(3)) AS c, CAST(NULL AS binary(2)) AS b,
            CAST(NULL AS varbinary(8)) AS vb, CAST(NULL AS varbinary(max)) AS vbmax,
            CAST(NULL AS nvarchar(7)) AS n, CAST(NULL AS nvarchar(max)) AS nmax,
            CAST(NULL AS nchar(3)) AS nc, CAST(NULL AS decimal(18,2)) AS amount,
            CAST(NULL AS numeric(12,4)) AS quantity, CAST(NULL AS datetime2(3)) AS stamp,
            CAST(NULL AS datetimeoffset(5)) AS zone, CAST(NULL AS time(7)) AS clock', 0, NULL);

SET @count = (SELECT COUNT(*) FROM @cases);
WHILE @i <= @count
BEGIN
    -- Arrange
    SELECT @name = name, @api = api, @expected = expected, @actual = actual,
        @expected_error = error_number, @expected_pattern = error_pattern
    FROM @cases WHERE id = @i;
    SELECT @error = 0, @error_message = NULL, @schema = N'stale output';
    DELETE @probes;
    INSERT @probes
        SELECT object_id FROM sys.views
        WHERE schema_id = SCHEMA_ID(N'test') AND name LIKE N'[_]query[_]schema[_]%';

    -- Act
    BEGIN TRY
        IF @api = 'D' EXEC test.assert_resultset_equals @name, @expected, @actual;
        ELSE IF @api = 'Q' EXEC test.assert_query_schemas_equal @name, @expected, @actual;
        ELSE IF @api = 'S' EXEC test.assert_schema_signature @name, @expected, @actual;
        ELSE EXEC test.get_query_schema @name, @actual, @schema OUTPUT;
    END TRY
    BEGIN CATCH
        SELECT @error = ERROR_NUMBER(), @error_message = ERROR_MESSAGE();
    END CATCH;

    -- Assert
    IF @error <> @expected_error OR
        (@expected_pattern IS NOT NULL AND COALESCE(@error_message, N'') NOT LIKE @expected_pattern)
        OR (@api = 'G' AND @expected_error = 0 AND
            (@schema IS NULL OR CONVERT(varbinary(max), @schema) <> CONVERT(varbinary(max), @expected)))
    BEGIN
        SET @failure = CONCAT(N'Assertion case failed: ', @name, N'; expected error ', @expected_error,
            N', got ', @error, N'; ', @error_message, N'; schema: ', @schema);
        THROW 51091, @failure, 1;
    END;
    IF EXISTS (
        SELECT object_id FROM sys.views
        WHERE schema_id = SCHEMA_ID(N'test') AND name LIKE N'[_]query[_]schema[_]%'
        EXCEPT SELECT object_id FROM @probes)
        OR EXISTS (
        SELECT object_id FROM @probes
        EXCEPT SELECT object_id FROM sys.views
        WHERE schema_id = SCHEMA_ID(N'test') AND name LIKE N'[_]query[_]schema[_]%')
        THROW 51091, 'A schema assertion leaked or removed a probe view.', 1;
    IF @@TRANCOUNT <> 0
        THROW 51091, 'An assertion changed the caller transaction count.', 1;
    PRINT CONCAT(N'PASS: ', @name);
    SET @i += 1;
END;
PRINT CONCAT(N'ASSERTION_PASS: ', @count, N' cases; no leaked probe views.');
