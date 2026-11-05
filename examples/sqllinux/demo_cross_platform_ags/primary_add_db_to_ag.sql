USE [master]
GO
ALTER AVAILABILITY GROUP [readscaleag] REMOVE DATABASE texasrangerstotheworldseries
GO
DROP DATABASE [texasrangerstotheworldseries]
GO
CREATE DATABASE [texasrangerstotheworldseries]
 ON  PRIMARY 
( NAME = N'texasrangerstotheworldseries', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\texasrangerstotheworldseries.mdf' , SIZE = 8192KB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB )
 LOG ON 
( NAME = N'texasrangerstotheworldseries_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\texasrangerstotheworldseries_log.ldf' , SIZE = 8192KB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB )
GO
BACKUP DATABASE texasrangerstotheworldseries to DISK = 'NUL'
go
ALTER AVAILABILITY GROUP [readscaleag] ADD DATABASE texasrangerstotheworldseries
GO