-- =============================================================================
-- Demo 4 — custom MCP tool source proc.
-- uspGetProductBOM: purpose-built wrapper keyed by product MODEL name so the
-- agent can ask by "Touring-1000" (matching the cold open) and get the FULL
-- multi-level, recursive bill of materials that the flat view can't express.
--
-- Deploy against the SAME instance DAB uses (localhost / AdventureWorks, Win auth).
-- Idempotent (CREATE OR ALTER). Wraps the stock dbo.uspGetBillOfMaterials.
-- =============================================================================
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.uspGetProductBOM
    @ProductModel nvarchar(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CheckDate datetime = GETDATE();

    -- Resolve the model name to a representative ProductID.
    DECLARE @pid int =
        (SELECT TOP (1) p.ProductID
         FROM Production.Product p
         JOIN Production.ProductModel pm ON pm.ProductModelID = p.ProductModelID
         WHERE pm.Name = @ProductModel
         ORDER BY p.ProductID);

    IF @pid IS NULL
    BEGIN
        -- Empty, well-typed result set so the tool degrades gracefully.
        -- Types match the real result set below.
        SELECT
            CAST(NULL AS int)            AS ProductAssemblyID,
            CAST(NULL AS int)            AS ComponentID,
            CAST(NULL AS nvarchar(50))   AS ComponentDesc,
            CAST(NULL AS decimal(38,2))  AS TotalQuantity,
            CAST(NULL AS money)          AS StandardCost,
            CAST(NULL AS money)          AS ListPrice,
            CAST(NULL AS smallint)       AS BOMLevel,
            CAST(NULL AS int)            AS RecursionLevel
        WHERE 1 = 0;
        RETURN;
    END;

    -- Full recursive, multi-level BOM (inlined from dbo.uspGetBillOfMaterials so
    -- the final SELECT is visible to sys.dm_exec_describe_first_result_set; a
    -- nested EXEC returns NULL there and makes the DAB config invalid).
    WITH BOM_cte (ProductAssemblyID, ComponentID, ComponentDesc, PerAssemblyQty, StandardCost, ListPrice, BOMLevel, RecursionLevel)
    AS (
        SELECT b.ProductAssemblyID, b.ComponentID, p.Name, b.PerAssemblyQty, p.StandardCost, p.ListPrice, b.BOMLevel, 0
        FROM Production.BillOfMaterials b
            INNER JOIN Production.Product p ON b.ComponentID = p.ProductID
        WHERE b.ProductAssemblyID = @pid
            AND @CheckDate >= b.StartDate
            AND @CheckDate <= ISNULL(b.EndDate, @CheckDate)
        UNION ALL
        SELECT b.ProductAssemblyID, b.ComponentID, p.Name, b.PerAssemblyQty, p.StandardCost, p.ListPrice, b.BOMLevel, RecursionLevel + 1
        FROM BOM_cte cte
            INNER JOIN Production.BillOfMaterials b ON b.ProductAssemblyID = cte.ComponentID
            INNER JOIN Production.Product p ON b.ComponentID = p.ProductID
        WHERE @CheckDate >= b.StartDate
            AND @CheckDate <= ISNULL(b.EndDate, @CheckDate)
    )
    SELECT
        b.ProductAssemblyID,
        b.ComponentID,
        b.ComponentDesc,
        SUM(b.PerAssemblyQty) AS TotalQuantity,
        b.StandardCost,
        b.ListPrice,
        b.BOMLevel,
        b.RecursionLevel
    FROM BOM_cte b
    GROUP BY b.ComponentID, b.ComponentDesc, b.ProductAssemblyID, b.BOMLevel, b.RecursionLevel, b.StandardCost, b.ListPrice
    ORDER BY b.BOMLevel, b.ProductAssemblyID, b.ComponentID
    OPTION (MAXRECURSION 25);
END;
GO
