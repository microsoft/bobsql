CREATE DATABASE WideWorldImporters   
    ON (FILENAME = '/var/opt/mssql/data/WideWorldImporters.mdf'),   
    (FILENAME = '/var/opt/mssql/data/WideWorldImporters_UserData.ndf'),
    (FILENAME = '/var/opt/mssql/data/WideWorldImporters.ldf'),
    (FILENAME = '/var/opt/mssql/data/WideWorldImporters_InMemory_Data_1')
    FOR ATTACH
GO