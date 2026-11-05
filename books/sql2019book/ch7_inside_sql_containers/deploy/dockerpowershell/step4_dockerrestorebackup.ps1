if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
docker exec --env SQLCMDPASSWORD -it sql2019latest /opt/mssql-tools/bin/sqlcmd -b -S localhost -U SA -Q "RESTORE DATABASE WideWorldImporters FROM DISK = '/var/opt/mssql/WideWorldImporters-Full.bak' WITH MOVE 'WWI_Primary' TO '/var/opt/mssql/data/WideWorldImporters.mdf', MOVE 'WWI_UserData' TO '/var/opt/mssql/data/WideWorldImporters_userdata.ndf', MOVE 'WWI_Log' TO '/var/opt/mssql/data/WideWorldImporters.ldf', MOVE 'WWI_InMemory_Data_1' TO '/var/opt/mssql/data/WideWorldImporters_InMemory_Data_1'"
if ($LASTEXITCODE -ne 0) { throw 'Demo SQL command failed.' }

if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
