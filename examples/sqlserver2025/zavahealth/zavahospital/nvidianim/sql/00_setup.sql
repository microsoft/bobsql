-- =============================================
-- Script: 00_setup.sql
-- Purpose: Create test database for NIM vector search demo
-- Note: Skip if FoundryLocalTest already exists from Foundry Local demo
-- =============================================
USE master;
GO

IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'FoundryLocalTest')
    CREATE DATABASE FoundryLocalTest;
GO

USE FoundryLocalTest;
GO

PRINT 'FoundryLocalTest database ready.';
GO
