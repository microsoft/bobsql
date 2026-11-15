/* ============================================================================
   Caldova Regional Care Transfer Center
   00-create-database.sql : create the SQL Server 2025 application database
   ============================================================================ */

USE [master];
GO

IF DB_ID(N'CaldovaRegionalCare') IS NULL
    CREATE DATABASE [CaldovaRegionalCare];
GO

ALTER DATABASE [CaldovaRegionalCare] SET COMPATIBILITY_LEVEL = 170;
ALTER DATABASE [CaldovaRegionalCare] SET READ_COMMITTED_SNAPSHOT ON;
GO

SELECT
    d.[name],
    d.compatibility_level,
    d.is_read_committed_snapshot_on
FROM sys.databases AS d
WHERE d.[name] = N'CaldovaRegionalCare';
GO