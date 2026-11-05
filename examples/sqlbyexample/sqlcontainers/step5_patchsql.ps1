if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
$env:MSSQL_SA_PASSWORD = $env:SQLCMDPASSWORD
docker stop sql2019ga
docker run `
 -e 'ACCEPT_EULA=Y' -e MSSQL_SA_PASSWORD `
 -p 1401:1433 `
 -v sql2019volume:/var/opt/mssql `
 --hostname sql2019cu4 `
 --name sql2019cu4 `
 -d `
 mcr.microsoft.com/mssql/server:2019-CU4-ubuntu-16.04
if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
