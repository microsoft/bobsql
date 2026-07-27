-- SQL MCP Server talk — opener object.
-- A single VIEW that answers "what parts make up <product>?" in ONE set-based query.
-- Keyed by PRODUCT MODEL name (e.g. 'Touring-1000') so the 8 color/size SKUs collapse
-- to one clean parts list. This is the "beauty of SQL" artifact: one declarative join,
-- written once, reviewable, exposed as one MCP tool (read_records) -> one tool call.
--
-- Deploy: sqlcmd -S localhost -E -C -b -d AdventureWorks -i 01-mcp-views.sql

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('mcp') IS NULL
    EXEC('CREATE SCHEMA mcp AUTHORIZATION dbo;');
GO

CREATE OR ALTER VIEW mcp.vProductComponents
AS
-- Component name is collapsed to the component's PRODUCT MODEL when it has one
-- (so 'HL Touring Frame - Blue, 46' ... 'Yellow, 60' fold into one 'HL Touring
-- Frame' row); purchased parts with no model fall back to the part name.
SELECT DISTINCT
    pm.Name                     AS ProductModel,   -- e.g. 'Touring-1000'
    COALESCE(cm.Name, c.Name)   AS ComponentName,  -- e.g. 'HL Touring Frame'
    bom.PerAssemblyQty          AS Quantity,
    um.Name                     AS UnitOfMeasure
FROM Production.ProductModel        AS pm
JOIN Production.Product             AS asm ON asm.ProductModelID    = pm.ProductModelID
JOIN Production.BillOfMaterials     AS bom ON bom.ProductAssemblyID = asm.ProductID
                                          AND bom.EndDate IS NULL
JOIN Production.Product             AS c   ON c.ProductID           = bom.ComponentID
LEFT JOIN Production.ProductModel   AS cm  ON cm.ProductModelID     = c.ProductModelID
LEFT JOIN Production.UnitMeasure    AS um  ON um.UnitMeasureCode     = bom.UnitMeasureCode;
GO
