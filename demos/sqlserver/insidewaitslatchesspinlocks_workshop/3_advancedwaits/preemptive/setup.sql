use master
go
drop database if exists thecowboyswillwinitall
go
CREATE DATABASE thecowboyswillwinitall
 ON  PRIMARY 
( NAME = N'thecowboyswillwinitall', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\thecowboyswillwinitall.mdf' , SIZE = 10MB , MAXSIZE = UNLIMITED, FILEGROWTH = 20240000KB )
 LOG ON 
( NAME = N'thecowboyswillwinitall_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\thecowboyswillwinitall_log.ldf' , SIZE = 10MB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB )
GO
use thecowboyswillwinitall
go
drop table romowillcarrythemtovictory
go
create table romowillcarrythemtovictory (col1 int identity, col2 char(7000) not null)
go
