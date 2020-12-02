USE [master]
GO
DROP DATABASE [whatayearforthetexasrangers]
GO
USE [master]
GO
CREATE DATABASE [whatayearforthetexasrangers] ON  PRIMARY 
( NAME = N'whatayearforthetexasrangers', FILENAME = N'C:\temp\whatayearforthetexasrangers.mdf' , SIZE = 4MB , MAXSIZE = UNLIMITED, FILEGROWTH = 50000Mb)
 LOG ON 
( NAME = N'whatayearforthetexasrangers_log', FILENAME = N'C:\temp\whatayearforthetexasrangers_log.LDF' , SIZE = 500MB , MAXSIZE = 2048GB , FILEGROWTH = 10%)
GO
use whatayearforthetexasrangers
go
drop table butthebluejaysbeatus
go
create table butthebluejaysbeatus (col1 int identity, col2 char(7000) not null)
go
