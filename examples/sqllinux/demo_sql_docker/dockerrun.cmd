@echo off
if not defined SQLCMDPASSWORD (
    echo Set SQLCMDPASSWORD privately before running this demo. 1>&2
    exit /b 1
)
set "MSSQL_SA_PASSWORD=%SQLCMDPASSWORD%"
docker run -e "ACCEPT_EULA=Y" -e MSSQL_SA_PASSWORD -p 1401:1433 --name sql1 -d microsoft/mssql-server-linux:2017-latest

exit /b %errorlevel%
