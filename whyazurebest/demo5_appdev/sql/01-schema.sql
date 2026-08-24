-- Demo 5 schema: the support ticket table that Change Event Streaming watches.
--
-- Deliberately NOT using the SQL Server 2025 `json` data type here. CES skips
-- json, xml, vector, sql_variant, geography/geometry and text/ntext columns
-- silently -- the row would stream with the payload column simply missing. The
-- ticket body is nvarchar(max); CES supports LOB columns (1 MB per column).
--
-- The primary key is created up front on purpose: while CES is enabled on a
-- table you cannot add or drop a primary key constraint.

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF OBJECT_ID('dbo.SupportTicket', 'U') IS NOT NULL
BEGIN
    PRINT 'dbo.SupportTicket already exists - leaving it alone.';
END
ELSE
BEGIN
    CREATE TABLE dbo.SupportTicket
    (
        TicketId     int            IDENTITY(1, 1) NOT NULL,
        CustomerName nvarchar(100)  NOT NULL,
        Severity     tinyint        NOT NULL,
        Subject      nvarchar(200)  NOT NULL,
        Body         nvarchar(max)  NULL,
        CreatedAt    datetime2(3)   NOT NULL
            CONSTRAINT DF_SupportTicket_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_SupportTicket PRIMARY KEY CLUSTERED (TicketId)
    );

    PRINT 'Created dbo.SupportTicket.';
END
GO

-- Left empty on purpose. CES does not seed rows that exist before it is
-- enabled, so an empty table guarantees the first event on stage is the row
-- typed in front of the audience.
