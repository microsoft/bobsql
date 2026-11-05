@echo off
setlocal
if not defined SQLCMDPASSWORD (
    echo Set SQLCMDPASSWORD privately before running this demo. 1>&2
    exit /b 1
)
if not defined SQLLINUXPASSWORD (
    echo Set SQLLINUXPASSWORD privately before running this demo. 1>&2
    exit /b 1
)
if not defined SqlLoginPassword (
    echo Set SQL-escaped SqlLoginPassword to match SQLLINUXPASSWORD. 1>&2
    exit /b 1
)
if "%~1"=="" (
    echo Supply the server name; passwords come from the environment. 1>&2
    exit /b 1
)
sqlcmd -b -Usa -icleanup.sql -S%1
if errorlevel 1 exit /b 1
sqlcmd -b -Usa -icreatelogin.sql -S%1
if errorlevel 1 exit /b 1
set "SQLCMDPASSWORD=%SQLLINUXPASSWORD%"
sqlcmd -b -Usqllinux -idropandcreatedb.sql -S%1
if errorlevel 1 exit /b 1
sqlcmd -b -Usqllinux -icreateschemas.sql -S%1
if errorlevel 1 exit /b 1
sqlcmd -b -Usqllinux -icreatesequences.sql -S%1
if errorlevel 1 exit /b 1
sqlcmd -b -Usqllinux -icreatepeople.sql -S%1
if errorlevel 1 exit /b 1
sqlcmd -b -Usqllinux -icreatecustomers.sql -S%1
if errorlevel 1 exit /b 1

exit /b %errorlevel%
