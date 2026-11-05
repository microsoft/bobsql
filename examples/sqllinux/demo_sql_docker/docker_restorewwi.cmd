@echo off
if not defined SQLCMDPASSWORD (
    echo Set SQLCMDPASSWORD privately before running this demo. 1>&2
    exit /b 1
)
docker exec --env SQLCMDPASSWORD -it sql1 /opt/mssql-tools/bin/sqlcmd -b -S localhost -U SA -Q "RESTORE DATABASE WideWorldImporters FROM DISK = '/var/opt/mssql/WideWorldImporters-Full.bak' WITH MOVE 'WWI_Primary' TO '/var/opt/mssql/data/WideWorldImporters.mdf', MOVE 'WWI_UserData' TO '/var/opt/mssql/data/WideWorldImporters_userdata.ndf', MOVE 'WWI_Log' TO '/var/opt/mssql/data/WideWorldImporters.ldf', MOVE 'WWI_InMemory_Data_1' TO '/var/opt/mssql/data/WideWorldImporters_InMemory_Data_1'"
exit /b %errorlevel%
