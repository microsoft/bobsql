ALTER DATABASE [iliketolosedata] SET SINGLE_USER;
GO
ALTER DATABASE [iliketolosedata] SET EMERGENCY;
GO
DBCC CHECKDB (N'iliketolosedata', REPAIR_ALLOW_DATA_LOSS) WITH ALL_ERRORMSGS, NO_INFOMSGS;
GO