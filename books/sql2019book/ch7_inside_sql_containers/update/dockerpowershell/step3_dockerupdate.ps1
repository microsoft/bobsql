if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
$env:MSSQL_SA_PASSWORD = $env:SQLCMDPASSWORD
docker stop sql2017CU10
docker run -e "ACCEPT_EULA=Y" -e MSSQL_SA_PASSWORD -p 1401:1433 --name sql2017latest --hostname sql2017latest -v sqlvolume:/var/opt/mssql -d mcr.microsoft.com/mssql/server:2017-latest-ubuntu

if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
