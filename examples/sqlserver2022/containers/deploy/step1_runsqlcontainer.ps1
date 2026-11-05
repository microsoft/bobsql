if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
$env:MSSQL_SA_PASSWORD = $env:SQLCMDPASSWORD
docker run `
 -e 'ACCEPT_EULA=Y' -e MSSQL_SA_PASSWORD `
 --hostname sql2022 `
 -p 1401:1433 `
 -v sql2022volume:/var/opt/mssql `
 --name sql2022 `
 -d `
 mcr.microsoft.com/mssql/server:2022-latest

if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
