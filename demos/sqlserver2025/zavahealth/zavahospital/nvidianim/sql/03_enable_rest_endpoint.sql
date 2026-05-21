-- =============================================
-- Script: 03_enable_rest_endpoint.sql
-- Purpose: Enable sp_invoke_external_rest_endpoint for SQL Server 2025
--          and grant permissions in FoundryLocalTest
-- Note: Skip if already enabled from Foundry Local demo
-- Prerequisite: Run against master with sysadmin
-- =============================================
USE master;
GO

-- Enable the external REST endpoint feature (disabled by default in SQL Server 2025)
EXEC sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;
GO

USE FoundryLocalTest;
GO

-- Grant permission to execute external REST endpoints
GRANT EXECUTE ANY EXTERNAL ENDPOINT TO [public];
GO

PRINT 'External REST endpoint enabled and permissions granted.';
GO
