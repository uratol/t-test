# SQL Server 2022+ local release check. Creates and drops only its own fresh database.
# Requires sqlcmd, Windows authentication, and permission to create a database.
param(
    [Parameter(Mandatory)] [string] $Server,
    [switch] $MutationChecks
)
$ErrorActionPreference = 'Stop'
$database = 'ttest_regression_' + [guid]::NewGuid().ToString('N')
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$owned = $false
$moduleConnection = $null

function Invoke-RegressionSql(
    [string] $Sql,
    [string] $Expected = '',
    [switch] $DuplicateErrors,
    [string] $TargetDatabase = $database
) {
    $file = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($file, $Sql)
        $arguments = @('-S', $Server, '-E', '-C', '-d', $TargetDatabase, '-l', '10', '-i', $file)
        if (-not $DuplicateErrors) { $arguments += '-b' }
        $output = & sqlcmd @arguments 2>&1
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"
        if ($exitCode -ne 0 -or
                ($DuplicateErrors -and ($text -match '(?m)^Msg (?!50000,)\d+,')) -or
                ($Expected -and $text -notmatch $Expected)) {
            throw ($output | Select-Object -Last 25 | Out-String)
        }
        if ($DuplicateErrors -and [regex]::Matches($text, '(?m)^Msg 50000,').Count -ne 2) {
            throw 'The framework suite did not emit exactly its two deliberate duplicate errors.'
        }
        return $text
    }
    finally { Remove-Item -LiteralPath $file }
}

function Read-Module([string] $Name) {
    $command = $moduleConnection.CreateCommand()
    $command.CommandText = 'SELECT OBJECT_DEFINITION(OBJECT_ID(@name));'
    $null = $command.Parameters.Add('@name', [System.Data.SqlDbType]::NVarChar, 128)
    $command.Parameters['@name'].Value = $Name
    try {
        $definition = $command.ExecuteScalar()
        if ($definition -isnot [string]) { throw "Missing mutation target: $Name" }
        # SQL Server stores ALTER definitions with a CREATE verb.
        return [regex]::Replace($definition.TrimStart(), '\ACREATE(?:\s+OR\s+ALTER)?\b', 'ALTER', 'IgnoreCase')
    }
    finally { $command.Dispose() }
}

function Write-Module([string] $Definition) {
    $command = $moduleConnection.CreateCommand()
    $command.CommandText = $Definition
    try { $null = $command.ExecuteNonQuery() }
    finally { $command.Dispose() }
}

try {
    $null = Invoke-RegressionSql -TargetDatabase master -Sql @"
IF CAST(SERVERPROPERTY('EngineEdition') AS int) NOT IN (2, 3, 4)
    OR CAST(SERVERPROPERTY('ProductMajorVersion') AS int) < 16
    THROW 51090, 'This local harness requires SQL Server 2022+.', 1;
IF DB_ID(N'$database') IS NOT NULL
    THROW 51090, 'Refusing to reuse an existing database.', 1;
CREATE DATABASE [$database];
"@
    $owned = $true
    Write-Output "Created isolated database: $database"
    $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $repo 'install.sql')) 'Installation and tests complete\.'
    & (Join-Path $PSScriptRoot 'installation-tests.ps1') -Server $Server -Database $database

    foreach ($path in @(
        'tests\regression\install-framework-coverage-tests.sql',
        'tests\samples\catalog\install-compare-resultset-tests.sql',
        'tests\samples\stdev\install-stdev-tests.sql',
        'tests\samples\select-star\install-select-star-tests.sql'
    )) {
        $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $repo $path))
    }
    Write-Output 'PASS: four optional installers (SELECT-star definitions only).'
    & (Join-Path $PSScriptRoot 'select-star-package-tests.ps1') -Server $Server -Database $database
    $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $PSScriptRoot 'api-tests.sql')) `
        '(?s)Succeded: 3, failed: 0, errors: 0.*API_PASS:'
    Write-Output 'PASS: API signatures, named arguments and compatibility alias.'

    $assertions = Get-Content -Raw (Join-Path $PSScriptRoot 'assertion-tests.sql')
    $null = Invoke-RegressionSql $assertions 'ASSERTION_PASS: 62 cases'
    Write-Output 'PASS: 62 assertion contracts and probe cleanup.'
    & (Join-Path $PSScriptRoot 'logger-tests.ps1') -Server $Server -Database $database
    $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $PSScriptRoot 'run-framework-coverage-tests.sql')) `
        'PASSED\s+49\s+0\s+0' -DuplicateErrors
    Write-Output 'PASS: 49 framework scenario groups (33 positive procedures / 41 cases).'
    $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $PSScriptRoot 'vector-tests.sql')) 'PASSED\s+37\s+0'
    Write-Output 'PASS: 37 vector scenario groups.'
    $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $PSScriptRoot 'dimension-tests.sql')) 'PASSED\s+29\s+0'
    Write-Output 'PASS: 29 dimension scenario groups.'
    & (Join-Path $PSScriptRoot 'runner-tests.ps1') -Server $Server -Database $database
    $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $repo 'tests\samples\catalog\run-compare-resultset-tests.sql')) `
        'Succeded: 13, failed: 0, errors: 0'
    $null = Invoke-RegressionSql (Get-Content -Raw (Join-Path $repo 'tests\samples\stdev\run-stdev-tests.sql')) `
        'Succeded: 28, failed: 0, errors: 0'
    $null = Invoke-RegressionSql "EXEC test.run @test_schemas = N'tests';" `
        '72 procedures selected\. Planned cases: 80, executed cases: 80\. Succeded: 80, failed: 0, errors: 0'
    Write-Output 'PASS: catalog/STDEV samples and all 72 bundled procedures / 80 cases.'

    if ($MutationChecks) {
        $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
        $builder['Data Source'] = $Server
        $builder['Initial Catalog'] = $database
        $builder['Integrated Security'] = $true
        $builder['Encrypt'] = $true
        $builder['TrustServerCertificate'] = $true
        $builder['Connect Timeout'] = 10
        $moduleConnection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
        $moduleConnection.Open()
        foreach ($target in @(
            'test.assert_resultset_equals', 'test.get_query_schema',
            'test.assert_schema_signature', 'test.assert_query_schemas_equal', 'test.log'
        )) {
            $original = Read-Module $target
            $body = [regex]::Match($original, '(?im)^[ \t]*AS[ \t]*\r?$')
            if (-not $original.StartsWith('ALTER') -or -not $body.Success) {
                throw "Cannot safely locate procedure signature/body: $target"
            }
            $mutant = $original.Substring(0, $body.Index) + "AS`nRETURN;"
            try {
                Write-Module $mutant
                if (-not [string]::Equals((Read-Module $target), $mutant, [StringComparison]::Ordinal)) {
                    throw "Mutation was not applied: $target"
                }
                $killed = $false
                try {
                    if ($target -eq 'test.log') {
                        & (Join-Path $PSScriptRoot 'logger-tests.ps1') -Server $Server -Database $database | Out-Null
                    } else {
                        $null = Invoke-RegressionSql $assertions 'ASSERTION_PASS: 62 cases'
                    }
                }
                catch {
                    if ($_.Exception.Message -notmatch "Assertion case failed:|Logger case '") { throw }
                    $killed = $true
                }
                if (-not $killed) { throw "Undetected return-only mutation: $target" }
                Write-Output "MUTANT_KILLED: $target"
            }
            finally {
                Write-Module $original
                if (-not [string]::Equals((Read-Module $target), $original, [StringComparison]::Ordinal)) {
                    throw "Original signature/body was not restored: $target"
                }
            }
        }
        $null = Invoke-RegressionSql $assertions 'ASSERTION_PASS: 62 cases'
        & (Join-Path $PSScriptRoot 'logger-tests.ps1') -Server $Server -Database $database | Out-Null
        Write-Output 'PASS: 5/5 return-only mutants detected; original modules restored and rechecked.'
    }
}
finally {
    if ($null -ne $moduleConnection) { $moduleConnection.Dispose() }
    [System.Data.SqlClient.SqlConnection]::ClearAllPools()
    if ($owned) {
        $null = Invoke-RegressionSql -TargetDatabase master -Sql "DROP DATABASE [$database];"
        Write-Output "Dropped isolated database: $database"
    }
}
Write-Output 'LOCAL_REGRESSION_PASS: SQL Server checks passed; Fabric execution and line/branch coverage are not measured.'
