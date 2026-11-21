# Native checks for SELECT-star packaging; extended projection syntax is not executed.
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database
)
$ErrorActionPreference = 'Stop'
$installer = Get-Content -Raw (Join-Path $PSScriptRoot '..\samples\select-star\install-select-star-tests.sql')
$runner = Get-Content -Raw (Join-Path $PSScriptRoot '..\samples\select-star\run-select-star-tests.sql')
# Execute registration setup without Fabric-only test queries on SQL Server.
$vectorSetup = $runner.Replace("EXEC test.run @test_schemas = N'select_star';", '')
$probe = 'user_probe_' + [guid]::NewGuid().ToString('N')
$owned = $false

function Invoke-PackageSql([string] $Sql) {
    $file = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($file, $Sql)
        $output = & sqlcmd -S $Server -d $Database -E -C -l 10 -b -i $file 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($output | Select-Object -Last 25 | Out-String) }
        return ($output -join "`n")
    }
    finally { Remove-Item -LiteralPath $file }
}

try {
    # Arrange
    $null = Invoke-PackageSql @"
IF OBJECT_ID(N'select_star.test', N'P') IS NULL
    OR OBJECT_ID(N'select_star.test_data', N'P') IS NULL
    THROW 51090, 'Install the vectorized SELECT-star package first.', 1;
IF OBJECT_ID(N'select_star.test_like_suffix') IS NOT NULL
    THROW 51090, 'Legacy fixture already exists; nothing was changed.', 1;
BEGIN TRAN;
EXEC(N'CREATE PROC select_star.test_like_suffix AS RETURN;');
EXEC(N'CREATE PROC select_star.[$probe] AS RETURN;');
INSERT test.test_vectors VALUES ('[select_star].[$probe]', '/* owned probe */');
COMMIT;
"@
    $owned = $true
    $null = Invoke-PackageSql @"
SELECT procedure_name, parameters INTO #before_install FROM test.test_vectors;
GO
-- Act
$installer
$installer
GO
IF EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM #before_install GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors GROUP BY procedure_name, parameters)
    OR EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM #before_install GROUP BY procedure_name, parameters)
    THROW 51091, 'Definition-only installation changed vector registrations.', 1;
SELECT procedure_name, parameters INTO #other_vectors
FROM test.test_vectors WHERE procedure_name NOT IN ('[select_star].[test]', '[select_star].[test_data]');
GO
$vectorSetup
$vectorSetup
GO
-- Assert
IF OBJECT_ID(N'select_star.test_like_suffix') IS NOT NULL
    OR OBJECT_ID(N'select_star.[$probe]', N'P') IS NULL
    THROW 51091, 'Package upgrade retained a retired test or removed a user procedure.', 1;
IF (SELECT COUNT(*) FROM test.test_vectors WHERE procedure_name = '[select_star].[test]') <> 30
    OR (SELECT COUNT(*) FROM test.test_vectors WHERE procedure_name = '[select_star].[test_data]') <> 4
    THROW 51091, 'Runner setup duplicated or omitted projection vectors.', 1;
IF EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM #other_vectors GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors
        WHERE procedure_name NOT IN ('[select_star].[test]', '[select_star].[test_data]') GROUP BY procedure_name, parameters)
    OR EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors
        WHERE procedure_name NOT IN ('[select_star].[test]', '[select_star].[test_data]') GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM #other_vectors GROUP BY procedure_name, parameters)
    THROW 51091, 'Runner setup changed unrelated registration rows.', 1;
IF OBJECT_ID(N'select_star.test_replace_arithmetic') IS NOT NULL
    OR OBJECT_ID(N'select_star.test_replace_null') IS NOT NULL
    OR OBJECT_ID(N'select_star.test_combined') IS NOT NULL
    OR OBJECT_ID(N'select_star.test_replace_same_type') IS NOT NULL
    OR OBJECT_ID(N'select_star.test_qualified_star') IS NOT NULL
    OR OBJECT_ID(N'select_star.test_correlated') IS NOT NULL
    THROW 51091, 'A replaced static procedure was not retired.', 1;
GO
-- Arrange
DECLARE @error int = 0;

-- Act
BEGIN TRY
    EXEC select_star.test @case_name = N'Native case-sensitive schema mismatch',
        @expected_columns = N'1 AS id', @star_expression = N'1 AS ID';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

-- Assert
IF @error <> 70001
    THROW 51091, 'The shared schema test accepted different column names.', 1;
EXEC select_star.test @case_name = N'Native metadata match',
    @expected_columns = N'1 AS id', @star_expression = N'99 AS id';
EXEC select_star.test @case_name = N'Native qualified alias',
    @expected_columns = N's.object_id', @star_expression = N's.object_id';
GO
-- Arrange
DECLARE @schema_error int = 0, @value_error int = 0;

-- Act
BEGIN TRY
    EXEC select_star.test_data @case_name = N'Equal JSON with different SQL types',
        @expected_columns = N'CAST(1 AS int) AS id', @star_expression = N'CAST(1 AS bigint) AS id';
END TRY
BEGIN CATCH
    SET @schema_error = ERROR_NUMBER();
END CATCH;
BEGIN TRY
    EXEC select_star.test_data @case_name = N'Equal schemas with different values',
        @expected_columns = N'1 AS id', @star_expression = N'2 AS id';
END TRY
BEGIN CATCH
    SET @value_error = ERROR_NUMBER();
END CATCH;

-- Assert
IF @schema_error <> 70001 OR @value_error <> 70001
    THROW 51091, 'The shared data test omitted schema or value comparison.', 1;
EXEC select_star.test_data @case_name = N'Native schema/data match',
    @expected_columns = N'1 AS id', @star_expression = N'1 AS id';
GO
DECLARE @arguments nvarchar(max), @call nvarchar(max);
SELECT @arguments = parameters FROM test.test_vectors
WHERE procedure_name = '[select_star].[test]' AND parameters LIKE '%test_plain:%';
IF @arguments IS NULL
    THROW 51091, 'The native-compatible plain-star vector is missing.', 1;
SET @call = N'EXEC select_star.test ' + @arguments;
EXEC sys.sp_executesql @call;
"@
    Write-Output 'SELECT_STAR_PACKAGE_PASS: definition-only installation; 30 schema and four data vectors; preserved registrations; alias binding and independent schema/value checks.'
}
finally {
    if ($owned) {
        $null = Invoke-PackageSql @"
DELETE test.test_vectors WHERE procedure_name = '[select_star].[$probe]';
DROP PROC IF EXISTS select_star.[$probe];
DROP PROC IF EXISTS select_star.test_like_suffix;
"@
    }
}
