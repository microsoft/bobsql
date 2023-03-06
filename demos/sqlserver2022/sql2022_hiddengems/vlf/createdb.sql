USE [master]
GO
DROP DATABASE IF EXISTS testvlf;
GO
CREATE DATABASE testvlf
 ON  PRIMARY 
( NAME = N'testvlf', FILENAME = N'C:\data\testvlf.mdf' , SIZE = 2GB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB)
 LOG ON 
( NAME = N'testvlf_log', FILENAME = N'c:\data\testvlf_log.ldf' , SIZE = 8MB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB);
GO