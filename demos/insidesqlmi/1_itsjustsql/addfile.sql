USE master;
GO
ALTER DATABASE gocowboys
ADD FILE
(
    NAME = newfile,
    FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\newfile.ndf',
    SIZE = 5MB,
    MAXSIZE = 100MB,
    FILEGROWTH = 5MB
);
ALTER DATABASE gocowboys
ADD FILE
(
    NAME = newfile,
    SIZE = 5MB,
    MAXSIZE = 100MB,
    FILEGROWTH = 5MB
);
GO


