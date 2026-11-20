# SQL Server 2022+ logger contracts. Captures actual InfoMessage/PRINT payloads.
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database
)
$ErrorActionPreference = 'Stop'
$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source'] = $Server
$builder['Initial Catalog'] = $Database
$builder['Integrated Security'] = $true
$builder['Encrypt'] = $true
$builder['TrustServerCertificate'] = $true
$builder['Connect Timeout'] = 10
$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
$messages = [System.Collections.Generic.List[string]]::new()
$connection.add_InfoMessage({
    param($sender, $eventArgs)
    foreach ($errorMessage in $eventArgs.Errors) {
        $messages.Add($errorMessage.Message)
    }
})
$passed = 0

function Read-Log([string] $Sql, [hashtable] $Parameters = @{}) {
    $messages.Clear()
    $command = $connection.CreateCommand()
    $command.CommandText = $Sql
    $command.CommandTimeout = 30
    foreach ($name in $Parameters.Keys) {
        $parameter = $command.Parameters.Add($name, [System.Data.SqlDbType]::NVarChar, -1)
        $parameter.Value = if ($null -eq $Parameters[$name]) { [DBNull]::Value } else { $Parameters[$name] }
    }
    try {
        $reader = $command.ExecuteReader()
        try {
            do {
                if ($reader.FieldCount -gt 0) { throw 'The logger returned an unexpected result grid.' }
            } while ($reader.NextResult())
        }
        finally { $reader.Dispose() }
    }
    finally { $command.Dispose() }
    return $messages.ToArray()
}

function Assert-Messages([string] $Name, [string[]] $Actual, [string[]] $Expected) {
    if ($Actual.Count -ne $Expected.Count) {
        throw "Logger case '$Name': expected $($Expected.Count) messages, got $($Actual.Count)."
    }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if (-not [string]::Equals($Actual[$i], $Expected[$i], [StringComparison]::Ordinal)) {
            throw "Logger case '$Name': message $i differs (expected $($Expected[$i].Length) UTF-16 units, got $($Actual[$i].Length))."
        }
    }
    $script:passed++
    Write-Output "PASS: $Name"
}

try {
    $connection.Open()

    # Arrange
    $sql = 'EXEC test.log @message = @message;'

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'plain' })

    # Assert
    Assert-Messages 'default severity' $actual @('DEBUG: plain')

    # Arrange
    $sql = @'
DECLARE @id int = OBJECT_ID(N'test.log');
EXEC test.log @message = N'Loaded %1: %2', @severity = N'info',
    @p1 = 7, @p2_str = N'quoted ''text''', @rowcount = 0, @proc_id = @id;
'@

    # Act
    $actual = @(Read-Log $sql)

    # Assert
    Assert-Messages 'formatting and metadata tail' $actual @("INFO: Loaded 7: quoted 'text' [ 0  rows] (SP: [test].[log])")

    # Arrange
    $sql = 'EXEC test.log @message = @message, @data = @data;'

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'inline'; '@data' = 'payload' })

    # Assert
    Assert-Messages 'inline data' $actual @('DEBUG: inline: payload ')

    # Arrange
    #N/A

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'empty'; '@data' = '' })

    # Assert
    Assert-Messages 'empty data' $actual @('DEBUG: empty:  ')

    # Arrange
    #N/A

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'no data'; '@data' = $null })

    # Assert
    Assert-Messages 'NULL data' $actual @('DEBUG: no data')

    # Arrange
    #N/A

    # Act
    $actual = @(Read-Log $sql @{ '@message' = '100% literal %s %d'; '@data' = $null })

    # Assert
    Assert-Messages 'literal format characters' $actual @('DEBUG: 100% literal %s %d')

    # Arrange
    $data = "first`rsecond"

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'lines'; '@data' = $data })

    # Assert
    Assert-Messages 'multiline data' $actual @('DEBUG: lines: ', $data)

    # Arrange
    $data = 'x' * 2033

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'x'; '@data' = $data })

    # Assert
    Assert-Messages 'exact inline boundary' $actual @("DEBUG: x: $data ")

    # Arrange
    $data += 'x'

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'x'; '@data' = $data })

    # Assert
    Assert-Messages 'inline boundary overflow' $actual @('DEBUG: x: ', $data)

    # Arrange
    $data = ('a' * 7999) + '  '

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'chunks'; '@data' = $data })

    # Assert
    Assert-Messages 'chunks preserve trailing spaces' $actual @('DEBUG: chunks: ', ('a' * 4000), (('a' * 3999) + ' '), ' ')

    # Arrange
    $pair = [char]::ConvertFromUtf32(0x1F600)
    $data = ('a' * 3999) + $pair + 'tail'

    # Act
    $actual = @(Read-Log $sql @{ '@message' = 'Unicode'; '@data' = $data })

    # Assert
    Assert-Messages 'surrogate pair across chunk boundary' $actual @('DEBUG: Unicode: ', ('a' * 3999), ($pair + 'tail'))

    # Arrange
    $message = ('m' * 2036) + $pair + 'tail'

    # Act
    $actual = @(Read-Log $sql @{ '@message' = $message; '@data' = $null })

    # Assert
    Assert-Messages 'header truncation preserves surrogate pairs' $actual @('DEBUG: ' + ('m' * 2036))

    # Arrange
    $tail = ' [ 7  rows] (SP: [test].[log])'
    $prefix = 'm' * (2044 - $tail.Length - 8)
    $message = $prefix + $pair + 'tail'
    $sql = @'
DECLARE @id int = OBJECT_ID(N'test.log');
EXEC test.log @message = @message, @rowcount = 7, @proc_id = @id;
'@

    # Act
    $actual = @(Read-Log $sql @{ '@message' = $message })

    # Assert
    Assert-Messages 'truncation retains the metadata tail' $actual @("DEBUG: $prefix$tail")

    Write-Output "LOGGER_PASS: $passed cases; exact message content and boundaries verified."
}
finally { $connection.Dispose() }
