USE [master]
GO
DROP DATABASE IF EXISTS [bigdb]
GO
CREATE DATABASE [bigdb]
 ON  PRIMARY 
( NAME = N'bigdb_Primary', FILENAME = N'/var/opt/mssql/data/bigdb.mdf' , SIZE = 5GB , MAXSIZE = 100GB, FILEGROWTH = 65536KB ), 
 FILEGROUP [USERDATA]  DEFAULT
( NAME = N'bigdb_UserData_1', FILENAME = N'/data1/bigdb_UserData_1.ndf' , SIZE = 10GB , MAXSIZE = 30GB, FILEGROWTH = 65536KB ),
( NAME = N'bigdb_UserData_2', FILENAME = N'/data2/bigdb_UserData_2.ndf' , SIZE = 10GB , MAXSIZE = 30GB, FILEGROWTH = 65536KB ),
( NAME = N'bigdb_UserData_3', FILENAME = N'/data3/bigdb_UserData_3.ndf' , SIZE = 10GB , MAXSIZE = 30GB, FILEGROWTH = 65536KB )
 LOG ON 
( NAME = N'big_Log', FILENAME = N'/log/bigdb_log.ldf' , SIZE = 10GB , MAXSIZE = 30GB , FILEGROWTH = 65536KB )
GO