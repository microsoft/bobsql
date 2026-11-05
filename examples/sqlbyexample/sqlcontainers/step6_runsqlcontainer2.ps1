if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
$env:MSSQL_SA_PASSWORD = $env:SQLCMDPASSWORD
docker run `
 -e 'ACCEPT_EULA=Y' -e MSSQL_SA_PASSWORD `
 --hostname sql2019ga2 `
 -p 1402:1433 -v `
 sql2019volume2:/var/opt/mssql `
 --name sql2019ga2 `
 -d `
 mcr.microsoft.com/mssql/server:2019-GA-ubuntu-16.04
if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
