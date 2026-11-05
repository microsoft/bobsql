if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
sqlcmd -b '-Usa' '-Slocalhost,1401' '-Q"USE WideWorldImporters;SELECT * FROM [Application].[People];"'
if ($LASTEXITCODE -ne 0) { throw 'Demo SQL command failed.' }
sqlcmd -b '-Usa' '-Slocalhost,1401' '-Q"SELECT @@VERSION"'
if ($LASTEXITCODE -ne 0) { throw 'Demo SQL command failed.' }


if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
