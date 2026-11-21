# SQL Server 2022 regression checks for schema/pattern selection and package runners.
# Requires Windows authentication and an existing dedicated database with T-TEST installed.
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database
)
$ErrorActionPreference = 'Stop'

function Invoke-CheckSql([string] $Sql) {
    $file = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($file, $Sql)
        $output = & sqlcmd -S $Server -d $Database -E -C -l 10 -b -i $file 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($output | Select-Object -Last 20 | Out-String)
        }
    }
    finally {
        Remove-Item -LiteralPath $file
    }
}

function Sql-Literal([string] $Text) {
    return "N'" + $Text.Replace("'", "''") + "'"
}

$id = [guid]::NewGuid().ToString('N')
$schema = "runner_probe_$id"
$otherSchema = "runnerXprobeX$id"
$bracketSchema = "runner[$id"
$trapSchema = ".$id"
$catalog = "[tests].[sys.objects@runner_$id]"
$stdev = "[tests].[stdev@runner_$id]"
$other = "[tests].[stdev_extra@runner_$id]"
$owned = $false
$procedures = [ordered]@{
    $catalog = "AS INSERT #runner_script_audit VALUES ('catalog');"
    $stdev = "AS INSERT #runner_script_audit VALUES ('stdev');"
    $other = "AS INSERT #runner_script_audit VALUES ('other');"
    "[$schema].[sys.objects@a]" = "AS INSERT #runner_script_audit VALUES ('a');"
    "[$schema].[stdev@b]" = "AS INSERT #runner_script_audit VALUES ('b');"
    "[$schema].[literal%_]]quoted]" = "AS INSERT #runner_script_audit VALUES ('literal');"
    "[$schema].[vector@case]" = "@n int = 0 AS INSERT #runner_script_audit VALUES (CONCAT('v', @n));"
    "[$otherSchema].[sys.objects@a]" = "AS INSERT #runner_script_audit VALUES ('wrong_schema');"
    "[$bracketSchema].[own]" = "AS INSERT #runner_script_audit VALUES ('bracket');"
    "[$trapSchema].[victim]" = "AS INSERT #runner_script_audit VALUES ('trap');"
}
$create = ($procedures.GetEnumerator() | ForEach-Object {
    'EXEC(' + (Sql-Literal "CREATE PROC $($_.Key) $($_.Value)") + ');'
}) -join "`n"
$cleanup = (($procedures.Keys | ForEach-Object {
    "DELETE FROM test.test_vectors WHERE procedure_name = $(Sql-Literal $_);"
    "IF OBJECT_ID(N'test.test_dimension_values', N'U') IS NOT NULL DELETE FROM test.test_dimension_values WHERE procedure_name = $(Sql-Literal $_);"
    "DROP PROC $_;"
}) -join "`n") + "`nDROP SCHEMA [$schema]; DROP SCHEMA [$otherSchema]; DROP SCHEMA [$bracketSchema]; DROP SCHEMA [$trapSchema];"
$catalogRun = Get-Content -Raw (Join-Path $PSScriptRoot '..\samples\catalog\run-compare-resultset-tests.sql')
$stdevRun = Get-Content -Raw (Join-Path $PSScriptRoot '..\samples\stdev\run-stdev-tests.sql')
$schemaScript = Get-Content -Raw (Join-Path $PSScriptRoot '..\samples\select-star\run-select-star-tests.sql')
# Test the runner's schema selection on native fixtures, not Fabric vector definitions.
$schemaCall = [regex]::Match($schemaScript, "EXEC test\.run @test_schemas = N'select_star';").Value
if (-not $schemaCall) { throw 'SELECT-star runner schema selection is missing.' }
$schemaRun = "EXEC test.set_registration_scope N'global';`n" + $schemaCall.Replace("N'select_star'", "N'$schema'")

function Assert-Selection([string] $Call, [string[]] $Expected, [int] $ErrorCode = 0) {
    $expectedRows = if ($Expected.Count) {
        'INSERT #runner_expected VALUES ' +
            (($Expected | ForEach-Object { '(' + (Sql-Literal $_) + ')' }) -join ',') + ';'
    } else { '' }
    Invoke-CheckSql @"
DECLARE @caught int = 0;

-- Arrange
CREATE TABLE #runner_script_audit (marker nvarchar(128));
CREATE TABLE #runner_expected (marker nvarchar(128));
$expectedRows

-- Act
BEGIN TRY
$Call
END TRY
BEGIN CATCH
    SET @caught = ERROR_NUMBER();
END CATCH;

-- Assert
IF @caught <> $ErrorCode
    THROW 51099, 'Runner selection raised an unexpected error.', 1;
IF EXISTS (
    SELECT marker, COUNT_BIG(*) FROM #runner_script_audit GROUP BY marker
    EXCEPT SELECT marker, COUNT_BIG(*) FROM #runner_expected GROUP BY marker)
    OR EXISTS (
    SELECT marker, COUNT_BIG(*) FROM #runner_expected GROUP BY marker
    EXCEPT SELECT marker, COUNT_BIG(*) FROM #runner_script_audit GROUP BY marker)
    THROW 51099, 'Runner selected the wrong procedures or invocation counts.', 1;
"@
}

try {
    Invoke-CheckSql @"
IF OBJECT_ID(N'test.run', N'P') IS NULL OR OBJECT_ID(N'test.test_procedures', N'V') IS NULL
    THROW 51090, 'Install the updated framework before running these checks.', 1;
IF SCHEMA_ID(N'$schema') IS NOT NULL OR SCHEMA_ID(N'$otherSchema') IS NOT NULL
    OR SCHEMA_ID(N'$bracketSchema') IS NOT NULL
    OR SCHEMA_ID(N'$trapSchema') IS NOT NULL
    THROW 51090, 'Probe names already exist; nothing was changed.', 1;
BEGIN TRY
    BEGIN TRAN;
    EXEC(N'CREATE SCHEMA [$schema] AUTHORIZATION dbo;');
    EXEC(N'CREATE SCHEMA [$otherSchema] AUTHORIZATION dbo;');
    EXEC(N'CREATE SCHEMA [$bracketSchema] AUTHORIZATION dbo;');
    EXEC(N'CREATE SCHEMA [$trapSchema] AUTHORIZATION dbo;');
    $create
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH;
"@
    $owned = $true
    Assert-Selection $catalogRun @('catalog')
    Assert-Selection $stdevRun @('stdev')
    Assert-Selection $schemaRun @('a', 'b', 'literal', 'v0')
    Assert-Selection "EXEC test.run @test_names = N'[$schema].%';" @('a', 'b', 'literal', 'v0')
    Assert-Selection "EXEC test.run @test_names = N'[$bracketSchema].%';" @('bracket')
    Assert-Selection "EXEC test.run @test_schemas = N'$trapSchema,$bracketSchema', @exclude_test_names = N'[$bracketSchema].%';" @('trap')
    Assert-Selection "EXEC test.run @test_names = N'[$schema].[sys.objects@a]';" @('a')
    Assert-Selection "EXEC test.run @test_names = N'[$schema].[literal%_]]quoted]';" @('literal')
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @test_names = N'%@a';" @('a')
    Assert-Selection "EXEC test.run @test_names = N'[$schema].%@[ab]';" @('a', 'b')
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @test_object_schemas = N'sys';" @('a')
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @exclude_test_object_schemas = N'sys';" @('b', 'literal', 'v0')
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @exclude_test_names = N'[$schema].%';" @()
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @exclude_test_schemas = N'$schema';" @()
    Assert-Selection "EXEC test.run @test_schemas = N' $schema , $otherSchema ', @test_names = N'%@a';" @('a', 'wrong_schema')
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @exclude_test_names = N'[$schema].%@[ab]|[$schema].literal%';" @('v0')
    Assert-Selection "EXEC test.run @test_names = N'[$schema].%does_not_exist';" @() 50000
    Assert-Selection "EXEC test.run @test_names = N'[$schema].[%]';" @() 50000
    Assert-Selection "EXEC test.run @test_names = N'[$schema].[_]';" @() 50000
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @exclude_test_names = N'[$schema].[%]|[$schema].[_]';" @('a', 'b', 'literal', 'v0')
    Assert-Selection "EXEC test.run @test_names = N'';" @() 50000
    Assert-Selection "EXEC test.run @test_names = N'[$Database].[$schema].[sys.objects@a]';" @() 50000
    Assert-Selection "EXEC test.run @test_schemas = N'missing_$id';" @() 70000
    Assert-Selection "EXEC test.run @test_schemas = N' ';" @() 70000
    Assert-Selection "EXEC test.run @test_names = N'[$schema].[sys.objects@a]|[$schema].[sys.objects@a]';" @('a', 'a') 50000
    Assert-Selection "DECLARE @long nvarchar(max) = REPLICATE(CAST(N'missing,' AS nvarchar(max)), 40) + N'$schema'; EXEC test.run @test_schemas = @long;" @('a', 'b', 'literal', 'v0')
    Assert-Selection "DECLARE @long nvarchar(max) = REPLICATE(CAST(N'missing,' AS nvarchar(max)), 40) + N'sys'; EXEC test.run @test_schemas = N'$schema', @test_object_schemas = @long;" @('a')
    Assert-Selection "EXEC test.run N'[$schema].%', N'[$schema].literal%', N'$schema,$otherSchema', N'$otherSchema', 1, N'INSERT #runner_script_audit VALUES (''callback'');', NULL, N'sys', N'missing';" @('callback', 'a')
    Assert-Selection "EXEC test.run N'[$schema].%', NULL, N'$schema', NULL, NULL, NULL, NULL, N'sys', N'sys';" @()

    Invoke-CheckSql @"
-- Arrange
EXEC test.set_registration_scope N'global';

-- Act
EXEC test.vector N'[$schema].[vector@case]', N'1';
EXEC test.vector N'[$schema].[vector@case]', N'2';

-- Assert
IF (SELECT COUNT(*) FROM test.test_vectors WHERE procedure_name = N'[$schema].[vector@case]') <> 2
    THROW 51099, 'Vector registration outside tests schema failed.', 1;
"@
    Assert-Selection "EXEC test.run @test_schemas = N'$schema', @test_names = N'%vector@case';" @('v1', 'v2')
    Assert-Selection $schemaRun @('a', 'b', 'literal', 'v1', 'v2')
    Invoke-CheckSql @"
-- Arrange
--N/A

-- Act
EXEC test.clear_registrations N'[$schema].[vector@case]';

-- Assert
IF EXISTS (SELECT 1 FROM test.test_vectors WHERE procedure_name = N'[$schema].[vector@case]')
    THROW 51099, 'Reset outside tests schema failed.', 1;
"@
    Assert-Selection @"
-- Arrange
CREATE TABLE #test_dimension_values (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);
EXEC test.set_registration_scope N'session';
EXEC test.dimension N'[$schema].[vector@case]', N'@n', N'[3,4]';

-- Act
EXEC test.run @test_names = N'[$schema].[vector@case]';
EXEC test.clear_registrations N'[$schema].[vector@case]';
EXEC test.run @test_names = N'[$schema].[vector@case]';

-- Assert
IF EXISTS (SELECT 1 FROM #test_dimension_values)
    THROW 51099, 'Reset did not clear custom-schema dimensions.', 1;
"@ @('v3', 'v4', 'v0')
    Write-Output 'Runner checks passed: schema/object filters, LIKE/exact names, exclusions, long lists, duplicates, registrations and package scripts.'
}
finally {
    if ($owned) {
        Invoke-CheckSql $cleanup
    }
}
