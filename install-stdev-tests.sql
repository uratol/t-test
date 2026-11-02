-- T-TEST STDEV tests for Fabric Warehouse / SQL Server 2022+.
-- Install the framework first, then run this entire file.
-- Creates/updates 27 self-contained test procedures and runs only those tests.
-- The small stdev@basic test is already in the basic package.
-- The tests remain installed; temporary reference tables are removed before running.
-- Example: EXEC test.run @test_names = N'[tests].[stdev@sin_1000]';
--
-- stdev is a concept, not a schema-qualified database object.
-- Concept@action tests skip object-existence checks in the naming validator.
-- Rerunning this file removes the 27 legacy math.stdev@action procedures.
-- STDEV is sample standard deviation (n - 1), not population STDEVP.
-- Series contain integers 1..n; LOG is natural logarithm and SIN uses radians.
-- Empty series and one sample must return NULL, not zero.
--
-- LOG/SIN references were computed independently with Python math.fsum:
-- values = [fn(i) for i in range(1, n + 1)]
-- mean = math.fsum(values) / n
-- expected = math.sqrt(math.fsum((x - mean)**2 for x in values) / (n - 1))
-- For untransformed 1..n, sample variance has the closed form n*(n+1)/12.
-- To add a size, add its references and increase @expected_test_count by three.
SET NOCOUNT ON;

IF @@TRANCOUNT > 0
	THROW 51090, 'Run the STDEV test registration outside a transaction.', 1;
IF SCHEMA_ID(N'tests') IS NULL OR OBJECT_ID(N'test.run', N'P') IS NULL
	OR OBJECT_ID(N'test.assert_equals', N'FN') IS NULL
	OR OBJECT_ID(N'test.assert_float_equals', N'FN') IS NULL
	OR OBJECT_ID(N'test.assert_null', N'FN') IS NULL
	THROW 51090, 'Install the T-TEST framework before running this file.', 1;

DECLARE @absolute_tolerance float = 1.0E-12,
	@relative_tolerance float = 1.0E-10,
	@expected_test_count int = 27;

DROP TABLE IF EXISTS #stvrv_references;
DROP TABLE IF EXISTS #stvrv_cases;

CREATE TABLE #stvrv_references (
	series_size int,
	log_stdev float NULL,
	sin_stdev float NULL
);
INSERT #stvrv_references (series_size, log_stdev, sin_stdev)
VALUES
	(0,      NULL,                   NULL),
	(1,      NULL,                   NULL),
	(2,      0.49012907173427356E0,   0.047960537094532095E0),
	(3,      0.55554836702486265E0,   0.42528195815059372E0),
	(10,     0.73302386571524281E0,   0.73047057675776728E0),
	(100,    0.92805318513601598E0,   0.71257270260367911E0),
	(1000,   0.9854629932739295E0,    0.70759635532427667E0),
	(10000,  0.99753151513917659E0,   0.7071388163856821E0),
	(100000, 0.9996244804083867E0,    0.70711040212720566E0);

CREATE TABLE #stvrv_cases (
	case_id int,
	series_size int,
	transformation varchar(8),
	procedure_name varchar(128),
	expected_stdev float NULL
);
INSERT #stvrv_cases (case_id, series_size, transformation, procedure_name, expected_stdev)
SELECT ROW_NUMBER() OVER (ORDER BY r.series_size, t.transformation),
	r.series_size, t.transformation,
	CONCAT('stdev@', t.transformation, '_', r.series_size),
	CASE t.transformation
		WHEN 'value' THEN
			CASE WHEN r.series_size < 2 THEN NULL
				ELSE SQRT(CONVERT(float, r.series_size) * (r.series_size + 1) / 12.0)
			END
		WHEN 'log' THEN r.log_stdev
		WHEN 'sin' THEN r.sin_stdev
	END
FROM #stvrv_references r
CROSS JOIN (VALUES ('value'), ('log'), ('sin')) t(transformation);

DECLARE @case_id int = 1,
	@case_count int = (SELECT COUNT(*) FROM #stvrv_cases),
	@unique_tests int = (SELECT COUNT(DISTINCT procedure_name) FROM #stvrv_cases),
	@series_size int, @transformation varchar(8), @procedure_name nvarchar(128),
	@expected float, @expression nvarchar(100), @sql nvarchar(max),
	@test_names nvarchar(max);

DECLARE @template nvarchar(max) = N'CREATE OR ALTER PROC [tests].{{procedure}}
AS
BEGIN
	SET NOCOUNT ON;
	PRINT N''Check STDEV for {{label}}, n={{size}}.'';
	PRINT N''Expect: NULL for n < 2; else reference within tolerance.'';

	DECLARE @actual float, @actual_count int, @assertion_result nvarchar(max),
		@expected float, @tolerance float, @message nvarchar(2048);

	-- Arrange
	SET @expected = {{expected}};
	SET @tolerance = {{absolute}} + {{relative}} * COALESCE(ABS(@expected), 0);

	-- Act
	SELECT @actual_count = COUNT(*), @actual = STDEV({{expression}})
	FROM GENERATE_SERIES(1, {{size}}, 1) s;

	-- Assert
	SET @assertion_result = test.assert_equals(
		N''GENERATE_SERIES must return {{size}} rows'', N''{{size}}'',
		CONVERT(nvarchar(12), @actual_count));
	SET @message = N''STDEV {{label}}, n={{size}} must match the reference'';
	IF @expected IS NULL
		SET @assertion_result = test.assert_null(@message, CONVERT(varbinary(max), @actual));
	ELSE
		SET @assertion_result = test.assert_float_equals(
			@message, @expected, @actual, @tolerance);
END;';

BEGIN TRY
	IF @case_count <> @expected_test_count OR @unique_tests <> @expected_test_count
		THROW 51090, 'Incomplete or duplicate STDEV test definitions.', 1;

	WHILE @case_id <= @case_count
	BEGIN
		SELECT @series_size = series_size, @transformation = transformation,
			@procedure_name = procedure_name, @expected = expected_stdev
		FROM #stvrv_cases WHERE case_id = @case_id;
		SET @expression = CASE @transformation
			WHEN 'value' THEN N'CONVERT(float, s.value)'
			WHEN 'log' THEN N'LOG(CONVERT(float, s.value))'
			WHEN 'sin' THEN N'SIN(CONVERT(float, s.value))'
		END;
		SET @sql = REPLACE(@template, N'{{procedure}}', QUOTENAME(@procedure_name));
		SET @sql = REPLACE(@sql, N'{{size}}', CONVERT(nvarchar(12), @series_size));
		SET @sql = REPLACE(@sql, N'{{expression}}', @expression);
		SET @sql = REPLACE(@sql, N'{{expected}}', COALESCE(CONVERT(nvarchar(32), @expected, 3), N'NULL'));
		SET @sql = REPLACE(@sql, N'{{absolute}}', CONVERT(nvarchar(32), @absolute_tolerance, 3));
		SET @sql = REPLACE(@sql, N'{{relative}}', CONVERT(nvarchar(32), @relative_tolerance, 3));
		SET @sql = REPLACE(@sql, N'{{label}}', @transformation);
		EXEC sys.sp_executesql @sql;
		SET @sql = N'DROP PROC IF EXISTS [tests].' + QUOTENAME(N'math.' + @procedure_name) + N';';
		EXEC sys.sp_executesql @sql;
		SET @case_id += 1;
	END;

	IF EXISTS (SELECT 1 FROM #stvrv_cases
		WHERE OBJECT_ID(N'[tests].' + QUOTENAME(procedure_name), N'P') IS NULL)
		THROW 51090, 'STDEV test registration is incomplete.', 1;

	SELECT @test_names = STRING_AGG(CONVERT(nvarchar(max), N'[tests].' + QUOTENAME(procedure_name)), N'|')
	FROM #stvrv_cases;
END TRY
BEGIN CATCH
	DROP TABLE #stvrv_cases;
	DROP TABLE #stvrv_references;
	THROW;
END CATCH;

DROP TABLE #stvrv_cases;
DROP TABLE #stvrv_references;
EXEC test.run @test_names = @test_names;
