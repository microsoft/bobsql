if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
$env:MSSQL_SA_PASSWORD = $env:SQLCMDPASSWORD
docker run -e "ACCEPT_EULA=Y" -e MSSQL_SA_PASSWORD -p 1401:1433 --name sql2019latest --hostname sql2019latest -d mcr.microsoft.com/mssql/rhel/server:2019-latest

if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
