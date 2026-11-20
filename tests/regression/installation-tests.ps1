# SQL Server 2022+ install/uninstall regressions in the specified dedicated database.
# Reinstalls the framework and checks guards, legacy retirement and non-destructive cleanup.
# Runs uninstall twice: execute before optional package installation, or use run-regression-tests.ps1.
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database
)
$ErrorActionPreference = 'Stop'
$installer = Get-Content -Raw (Join-Path $PSScriptRoot '..\..\install.sql')
$uninstaller = Get-Content -Raw (Join-Path $PSScriptRoot '..\..\uninstall.sql')
$legacyOwned = $false
$lifecycleOwned = $false
$restoreFramework = $false
$createdDimensionStore = $false
$upgradeOwned = $false
$schema = 'installation_probe_' + [guid]::NewGuid().ToString('N')
$installBatches = @([regex]::Split($installer, '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() })

function Invoke-InstallationSql([string] $Sql, [switch] $AllowGuardErrors) {
    $file = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($file, $Sql)
        $arguments = @('-S', $Server, '-d', $Database, '-E', '-C', '-l', '10', '-i', $file)
        if (-not $AllowGuardErrors) {
            $arguments += '-b'
        }
        $output = & sqlcmd @arguments 2>&1
        $result = $output -join "`n"
        if ($LASTEXITCODE -ne 0 -or ($AllowGuardErrors -and
                ($output | Where-Object { "$_" -match '^Msg (?!50000,)\d+' }))) {
            throw ($output | Select-Object -Last 20 | Out-String)
        }
        return $result
    }
    finally {
        Remove-Item -LiteralPath $file
    }
}

$null = Invoke-InstallationSql @"
IF OBJECT_ID(N'test.run', N'P') IS NULL
    THROW 51090, 'Install the framework before running installation checks.', 1;
IF OBJECT_ID(N'test.error') IS NOT NULL
    THROW 51090, 'Legacy fixture collision; nothing was changed.', 1;
IF OBJECT_ID(N'test.set_scope') IS NOT NULL OR OBJECT_ID(N'test.reset') IS NOT NULL
    OR OBJECT_ID(N'test.is_float_equals') IS NOT NULL
    OR OBJECT_ID(N'test.assert_schema') IS NOT NULL OR OBJECT_ID(N'test.assert_schema_equals') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.assert_schema_equals]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.set_scope@fc_context]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.set_registration_scope@fc_context]') IS NOT NULL
    OR EXISTS (SELECT 1 FROM test.test_vectors
        WHERE procedure_name IN (N'[tests].[test.set_scope@fc_context]', N'[tests].[test.set_registration_scope@fc_context]',
            N'[tests].[test.assert_schema_equals]', N'[tests].[test.assert_query_schemas_equal]'))
    THROW 51090, 'Run lifecycle checks before optional scope-test installation.', 1;
IF OBJECT_ID(N'test.test_dimension_values', N'U') IS NOT NULL
    EXEC(N'IF EXISTS (SELECT 1 FROM test.test_dimension_values
        WHERE procedure_name IN (N''[tests].[test.set_scope@fc_context]'', N''[tests].[test.set_registration_scope@fc_context]'',
            N''[tests].[test.assert_schema_equals]'', N''[tests].[test.assert_query_schemas_equal]''))
        THROW 51090, ''Scope-test dimension fixture collision; nothing was changed.'', 1;');
"@

# Arrange
$callerSetup = @"
SET XACT_ABORT OFF;
CREATE TABLE #installation_caller (value int, xact_abort int);
BEGIN TRAN;
INSERT #installation_caller VALUES (42, @@OPTIONS & 16384);
GO
"@
$callerAssert = @"
GO
-- Assert
DECLARE @preserved bit = IIF(@@TRANCOUNT = 1
    AND XACT_STATE() = 1
    AND EXISTS (SELECT 1 FROM #installation_caller WHERE value = 42 AND xact_abort = (@@OPTIONS & 16384)), 1, 0);
DECLARE @modules_preserved bit = IIF(OBJECT_ID(N'test.run', N'P') IS NOT NULL
    AND OBJECT_ID(N'[tests].[test.assert_equals]', N'P') IS NOT NULL, 1, 0);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @preserved = 0
    THROW 51099, 'A lifecycle guard damaged the caller transaction.', 1;
IF @modules_preserved = 0
    THROW 51099, 'A rejected lifecycle script removed framework objects.', 1;
PRINT 'PASS: caller transaction preserved.';
"@

foreach ($xactAbort in @('OFF', 'ON')) {
    foreach ($script in @(
        @{ Name = 'install.sql'; Text = $installer; Guards = 2 },
        @{ Name = 'uninstall.sql'; Text = $uninstaller; Guards = 1 }
    )) {
        # Arrange
        $setup = $callerSetup.Replace('SET XACT_ABORT OFF;', "SET XACT_ABORT $xactAbort;")

        # Act: deliberately continue across GO after guard errors, as an editor can.
        $result = Invoke-InstallationSql ($setup + "`n" + $script.Text + "`n" + $callerAssert) -AllowGuardErrors

        # Assert
        $guardPattern = '(?m)^Run ' + [regex]::Escape($script.Name) + ' outside a transaction\.\r?$'
        if ($result -notmatch '(?m)^PASS: caller transaction preserved\.\r?$' -or
                [regex]::Matches($result, '(?m)^Msg 50000,').Count -ne $script.Guards -or
                [regex]::Matches($result, $guardPattern).Count -ne $script.Guards) {
            throw "$($script.Name) did not reject and preserve the caller transaction with XACT_ABORT $xactAbort."
        }
    }

    foreach ($guard in @(
        @{ Text = $installBatches[0]; Message = 'Run install.sql outside a transaction.' },
        @{ Text = $installBatches[-1]; Message = 'Run install.sql outside a transaction.' },
        @{ Text = $uninstaller; Message = 'Run uninstall.sql outside a transaction.' }
    )) {
        # Arrange
        $expectedOption = if ($xactAbort -eq 'ON') { 16384 } else { 0 }

        # Act
        $null = Invoke-InstallationSql @"
SET XACT_ABORT $xactAbort;
CREATE TABLE #uninstall_caller (value int);
BEGIN TRAN;
INSERT #uninstall_caller VALUES (42);
DECLARE @error int = 0, @message nvarchar(max);
BEGIN TRY
$($guard.Text)
END TRY
BEGIN CATCH
    SELECT @error = ERROR_NUMBER(), @message = ERROR_MESSAGE();
END CATCH;

-- Assert
DECLARE @preserved bit = IIF(@@TRANCOUNT = 1 AND XACT_STATE() = 1
    AND EXISTS (SELECT 1 FROM #uninstall_caller WHERE value = 42)
    AND (@@OPTIONS & 16384) = $expectedOption, 1, 0);
DECLARE @modules_preserved bit = IIF(OBJECT_ID(N'test.run', N'P') IS NOT NULL, 1, 0);
DECLARE @diagnostic nvarchar(2048) = CONCAT(N'Caught lifecycle rejection: error=', @error,
    N'; message=', @message, N'; state=', XACT_STATE(), N'; count=', @@TRANCOUNT,
    N'; XACT_ABORT=', @@OPTIONS & 16384, N'; expected=$expectedOption; preserved=', @preserved);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @error <> 50000 OR @message <> N'$($guard.Message)' OR @preserved = 0
    THROW 51099, @diagnostic, 1;
IF @modules_preserved = 0
    THROW 51099, 'Caught lifecycle rejection removed framework objects.', 1;
"@
    }
}

try {
    # Arrange
    $null = Invoke-InstallationSql @"
IF OBJECT_ID(N'test.error') IS NOT NULL
    THROW 51090, 'Legacy fixture collision; nothing was changed.', 1;
EXEC(N'CREATE FUNCTION [test].[error]() RETURNS int AS BEGIN RETURN NULL; END;');
"@
    $legacyOwned = $true

    # Act
    $null = Invoke-InstallationSql $installer

    # Assert
    $null = Invoke-InstallationSql @"
IF OBJECT_ID(N'test.error', N'FN') IS NOT NULL
    THROW 51099, 'Installation retained the retired legacy sentinel.', 1;
IF OBJECT_ID(N'test.fail_no_error', N'P') IS NULL
    THROW 51099, 'Installation did not retain the replacement procedure.', 1;
"@

    # Arrange
    $fixtureResult = Invoke-InstallationSql @"
DECLARE @created bit = 0;
BEGIN TRY
    BEGIN TRAN;
    IF OBJECT_ID(N'test.test_dimension_values', N'U') IS NULL
    BEGIN
        CREATE TABLE test.test_dimension_values (
            procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
            parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
            value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
        );
        SET @created = 1;
    END;
    EXEC(N'CREATE SCHEMA [$schema] AUTHORIZATION dbo;');
    EXEC(N'CREATE PROC [$schema].[probe] @n int = 0 AS RETURN;');
    CREATE TABLE [$schema].[caller_data] (value int);
    INSERT [$schema].[caller_data] VALUES (42);
    EXEC test.set_registration_scope N'global';
    EXEC test.vector N'[$schema].[probe]', N'7';
    EXEC test.dimension N'[$schema].[probe]', N'@n', N'[8,9]';
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH;
IF @created = 1 PRINT 'CREATED_DIMENSION_STORE';
"@
    $lifecycleOwned = $true
    $createdDimensionStore = $fixtureResult -match '(?m)^CREATED_DIMENSION_STORE\r?$'
    $restoreFramework = $true

    # Arrange: model an older deployment, including duplicate saved registrations.
    $null = Invoke-InstallationSql @"
BEGIN TRAN;
EXEC(N'CREATE PROC test.set_scope @scope nvarchar(max) AS RETURN;');
EXEC(N'CREATE PROC test.reset @test_name nvarchar(max) = NULL AS RETURN;');
EXEC(N'CREATE FUNCTION test.is_float_equals(@expected float, @actual float, @tolerance float)
    RETURNS bit AS BEGIN RETURN 0; END;');
EXEC(N'CREATE PROC [tests].[test.set_scope@fc_context] AS RETURN;');
EXEC(N'CREATE PROC test.assert_schema @message nvarchar(max),
    @expected_schema nvarchar(max), @actual_query nvarchar(max) AS RETURN;');
EXEC(N'CREATE PROC test.assert_schema_equals @message nvarchar(max),
    @expected_query nvarchar(max), @actual_query nvarchar(max) AS RETURN;');
EXEC(N'CREATE PROC [tests].[test.assert_schema_equals] AS RETURN;');
INSERT test.test_vectors VALUES
    ('[tests].[test.set_scope@fc_context]', '/* retained */'),
    ('[tests].[test.set_scope@fc_context]', '/* retained */'),
    ('[tests].[test.assert_schema_equals]', '/* retained */'),
    ('[tests].[test.assert_schema_equals]', '/* retained */');
INSERT test.test_dimension_values VALUES
    ('[tests].[test.set_scope@fc_context]', '@retained', '7'),
    ('[tests].[test.set_scope@fc_context]', '@retained', '7');
COMMIT;
"@
    $upgradeOwned = $true

    # Act: a rejected upgrade must not migrate data or retire old names across GO.
    $legacyAssert = $callerAssert.Replace('IF @@TRANCOUNT > 0 ROLLBACK;', @'
IF OBJECT_ID(N'test.set_scope', N'P') IS NULL OR OBJECT_ID(N'test.reset', N'P') IS NULL
    OR OBJECT_ID(N'test.is_float_equals', N'FN') IS NULL
    OR OBJECT_ID(N'test.assert_schema', N'P') IS NULL OR OBJECT_ID(N'test.assert_schema_equals', N'P') IS NULL
    OR OBJECT_ID(N'[tests].[test.assert_schema_equals]', N'P') IS NULL
    OR (SELECT COUNT(*) FROM test.test_vectors WHERE procedure_name = '[tests].[test.assert_schema_equals]') <> 2
    OR OBJECT_ID(N'[tests].[test.set_scope@fc_context]', N'P') IS NULL
    OR (SELECT COUNT(*) FROM test.test_vectors WHERE procedure_name = '[tests].[test.set_scope@fc_context]') <> 2
    OR (SELECT COUNT(*) FROM test.test_dimension_values WHERE procedure_name = '[tests].[test.set_scope@fc_context]') <> 2
    SET @modules_preserved = 0;
IF @@TRANCOUNT > 0 ROLLBACK;
'@)
    foreach ($xactAbort in @('OFF', 'ON')) {
        $setup = $callerSetup.Replace('SET XACT_ABORT OFF;', "SET XACT_ABORT $xactAbort;")
        $result = Invoke-InstallationSql ($setup + "`n" + $installer + "`n" + $legacyAssert) -AllowGuardErrors

        # Assert
        if ($result -notmatch '(?m)^PASS: caller transaction preserved\.\r?$' -or
                [regex]::Matches($result, '(?m)^Msg 50000,').Count -ne 2) {
            throw "Rejected API upgrade changed old modules/registrations with XACT_ABORT $xactAbort."
        }
    }

    # Act: upgrade twice without clearing either registry.
    $null = Invoke-InstallationSql @"
SELECT CASE WHEN procedure_name = '[tests].[test.set_scope@fc_context]'
    THEN '[tests].[test.set_registration_scope@fc_context]'
    WHEN procedure_name = '[tests].[test.assert_schema_equals]'
    THEN '[tests].[test.assert_query_schemas_equal]' ELSE procedure_name END AS procedure_name,
    parameters INTO #expected_vectors FROM test.test_vectors;
SELECT CASE WHEN procedure_name = '[tests].[test.set_scope@fc_context]'
    THEN '[tests].[test.set_registration_scope@fc_context]'
    WHEN procedure_name = '[tests].[test.assert_schema_equals]'
    THEN '[tests].[test.assert_query_schemas_equal]' ELSE procedure_name END AS procedure_name,
    parameter_name, value INTO #expected_dimensions FROM test.test_dimension_values;
GO
$installer
$installer
GO
-- Assert
IF OBJECT_ID(N'test.set_scope') IS NOT NULL OR OBJECT_ID(N'test.reset') IS NOT NULL
    OR OBJECT_ID(N'test.is_float_equals') IS NOT NULL
    OR OBJECT_ID(N'test.assert_schema') IS NOT NULL OR OBJECT_ID(N'test.assert_schema_equals') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.assert_schema_equals]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.assert_query_schemas_equal]', N'P') IS NULL
    OR OBJECT_ID(N'[tests].[test.set_scope@fc_context]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.set_registration_scope@fc_context]', N'P') IS NULL
    THROW 51099, 'API upgrade did not replace deprecated modules.', 1;
IF EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM #expected_vectors GROUP BY procedure_name, parameters)
    OR EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM #expected_vectors GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors GROUP BY procedure_name, parameters)
    THROW 51099, 'API upgrade changed saved vector values or multiplicity.', 1;
IF EXISTS (
    SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM test.test_dimension_values GROUP BY procedure_name, parameter_name, value
    EXCEPT SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM #expected_dimensions GROUP BY procedure_name, parameter_name, value)
    OR EXISTS (
    SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM #expected_dimensions GROUP BY procedure_name, parameter_name, value
    EXCEPT SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM test.test_dimension_values GROUP BY procedure_name, parameter_name, value)
    THROW 51099, 'API upgrade changed saved dimension values or multiplicity.', 1;
"@

    # Arrange
    $null = Invoke-InstallationSql @"
DROP PROC [tests].[test.set_registration_scope@fc_context];
EXEC(N'CREATE PROC [tests].[test.set_scope@fc_context] AS RETURN;');
UPDATE test.test_vectors SET procedure_name = '[tests].[test.set_scope@fc_context]'
    WHERE procedure_name = '[tests].[test.set_registration_scope@fc_context]';
UPDATE test.test_dimension_values SET procedure_name = '[tests].[test.set_scope@fc_context]'
    WHERE procedure_name = '[tests].[test.set_registration_scope@fc_context]';
"@

    # Act
    $null = Invoke-InstallationSql (Get-Content -Raw (Join-Path $PSScriptRoot 'install-framework-coverage-tests.sql'))

    # Assert: native-only function names must not be bound while creating the module.
    $null = Invoke-InstallationSql @"
DECLARE @definition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'[tests].[test.set_registration_scope@fc_context]'));
IF @definition IS NULL THROW 51099, 'Scope self-test was not installed.', 1;
SET @definition = REPLACE(@definition, N'[tests].[test.set_registration_scope@fc_context]',
    N'[$schema].[scope_compile_probe]');
SET @definition = REPLACE(@definition, N'SQL_VARIANT_PROPERTY', N'__ttest_unsupported_native_function');
EXEC sys.sp_executesql @definition;
DROP PROC [$schema].[scope_compile_probe];
"@

    # Assert
    $null = Invoke-InstallationSql @"
IF OBJECT_ID(N'[tests].[test.set_scope@fc_context]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.set_registration_scope@fc_context]', N'P') IS NULL
    OR EXISTS (SELECT 1 FROM test.test_vectors WHERE procedure_name = '[tests].[test.set_scope@fc_context]')
    OR EXISTS (SELECT 1 FROM test.test_dimension_values WHERE procedure_name = '[tests].[test.set_scope@fc_context]')
    OR (SELECT COUNT(*) FROM test.test_vectors
        WHERE procedure_name = '[tests].[test.set_registration_scope@fc_context]' AND parameters = '/* retained */') <> 2
    OR (SELECT COUNT(*) FROM test.test_dimension_values
        WHERE procedure_name = '[tests].[test.set_registration_scope@fc_context]' AND parameter_name = '@retained' AND value = '7') <> 2
    THROW 51099, 'Optional package upgrade lost the scope self-test or saved registrations.', 1;
EXEC(N'CREATE PROC test.set_scope @scope nvarchar(max) AS RETURN;');
EXEC(N'CREATE PROC test.reset AS RETURN;');
EXEC(N'CREATE FUNCTION test.is_float_equals(@expected float, @actual float, @tolerance float)
    RETURNS bit AS BEGIN RETURN 0; END;');
EXEC(N'CREATE PROC [tests].[test.set_scope@fc_context] AS RETURN;');
EXEC(N'CREATE PROC test.assert_schema AS RETURN;');
EXEC(N'CREATE PROC test.assert_schema_equals AS RETURN;');
EXEC(N'CREATE PROC [tests].[test.assert_schema_equals] AS RETURN;');
"@

    # Act
    $null = Invoke-InstallationSql @"
SELECT procedure_name, parameters INTO #saved_vectors FROM test.test_vectors;
SELECT procedure_name, parameter_name, value INTO #saved_dimensions FROM test.test_dimension_values;
$uninstaller
$uninstaller

-- Assert
IF EXISTS (
    SELECT 1 FROM sys.objects
    WHERE schema_id = SCHEMA_ID(N'test') AND type IN ('P', 'FN', 'V') AND name IN (
        N'throw', N'fail_no_error', N'assert_equals', N'assert_float_equals',
        N'assert_null', N'assert_not_null', N'assert_error', N'assert_resultset_equals',
        N'get_query_schema', N'assert_schema_signature', N'assert_query_schemas_equal', N'log',
        N'set_registration_scope', N'vector', N'dimension', N'clear_registrations', N'run',
        N'throw_error', N'fail', N'format_message', N'is_json_equal', N'is_equal',
        N'is_equals', N'is_float_equal', N'is_null', N'is_not_null', N'test_procedures', N'test',
        N'set_scope', N'reset', N'is_float_equals', N'assert_schema', N'assert_schema_equals'))
    THROW 51099, 'Uninstall retained a public framework module.', 1;
IF OBJECT_ID(N'[tests].[test.set_scope@fc_context]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.set_registration_scope@fc_context]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.assert_schema_equals]') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.assert_query_schemas_equal]') IS NOT NULL
    THROW 51099, 'Uninstall retained an old or new scope self-test.', 1;
IF OBJECT_ID(N'[$schema].[probe]', N'P') IS NULL OR SCHEMA_ID(N'tests') IS NULL
    OR SCHEMA_ID(N'test') IS NULL
    OR (SELECT COUNT(*) FROM [$schema].[caller_data] WHERE value = 42) <> 1
    THROW 51099, 'Uninstall removed a custom procedure, schema or caller data.', 1;
IF EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM #saved_vectors GROUP BY procedure_name, parameters)
    OR EXISTS (
    SELECT procedure_name, parameters, COUNT_BIG(*) FROM #saved_vectors GROUP BY procedure_name, parameters
    EXCEPT SELECT procedure_name, parameters, COUNT_BIG(*) FROM test.test_vectors GROUP BY procedure_name, parameters)
    THROW 51099, 'Uninstall changed the vector registry multiset.', 1;
IF EXISTS (
    SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM test.test_dimension_values GROUP BY procedure_name, parameter_name, value
    EXCEPT SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM #saved_dimensions GROUP BY procedure_name, parameter_name, value)
    OR EXISTS (
    SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM #saved_dimensions GROUP BY procedure_name, parameter_name, value
    EXCEPT SELECT procedure_name, parameter_name, value, COUNT_BIG(*) FROM test.test_dimension_values GROUP BY procedure_name, parameter_name, value)
    THROW 51099, 'Uninstall changed the dimension registry multiset.', 1;
PRINT 'PASS: repeated uninstall preserved user objects and both registries.';
"@
    Write-Output 'Installation checks passed: transaction guards, API/package upgrades, idempotent uninstall and registry/user-data preservation.'
}
finally {
    if ($upgradeOwned) {
        $null = Invoke-InstallationSql @"
DELETE test.test_vectors WHERE procedure_name IN
    ('[tests].[test.set_scope@fc_context]', '[tests].[test.set_registration_scope@fc_context]',
     '[tests].[test.assert_schema_equals]', '[tests].[test.assert_query_schemas_equal]');
DELETE test.test_dimension_values WHERE procedure_name IN
    ('[tests].[test.set_scope@fc_context]', '[tests].[test.set_registration_scope@fc_context]',
     '[tests].[test.assert_schema_equals]', '[tests].[test.assert_query_schemas_equal]');
"@
    }
    if ($restoreFramework) {
        $null = Invoke-InstallationSql $installer
    }
    if ($lifecycleOwned) {
        $dropDimensionStore = if ($createdDimensionStore) {
            'IF NOT EXISTS (SELECT 1 FROM test.test_dimension_values) DROP TABLE test.test_dimension_values;'
        } else { '' }
        $null = Invoke-InstallationSql @"
DELETE test.test_vectors WHERE procedure_name = N'[$schema].[probe]';
DELETE test.test_dimension_values WHERE procedure_name = N'[$schema].[probe]';
$dropDimensionStore
DROP PROC IF EXISTS [$schema].[scope_compile_probe];
DROP PROC [$schema].[probe];
DROP TABLE [$schema].[caller_data];
DROP SCHEMA [$schema];
"@
    }
    if ($legacyOwned) {
        $null = Invoke-InstallationSql 'DROP FUNCTION IF EXISTS [test].[error];'
    }
}
