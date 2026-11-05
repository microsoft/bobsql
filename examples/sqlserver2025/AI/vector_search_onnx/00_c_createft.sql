/*
Creates an FT index on Production.ProductDescription(Description) using the existing PK.
Safe to re-run.
*/

USE [AdventureWorks];  -- <-- Change if your DB is AdventureWorks2019/2022/etc.
GO

-- 1) Ensure Full-Text Search is installed
IF 1 = ISNULL(CONVERT(int, FULLTEXTSERVICEPROPERTY('IsFullTextInstalled')), 0)
BEGIN
    PRINT 'Full-Text Search feature is installed.';
END
ELSE
BEGIN
    RAISERROR('Full-Text Search feature is not installed on this instance.', 16, 1);
    RETURN;
END
GO

-- 2) Create a full-text catalog if not present
IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'FTC_AdventureWorks')
BEGIN
    PRINT 'Creating full-text catalog [FTC_AdventureWorks]...';
    CREATE FULLTEXT CATALOG [FTC_AdventureWorks];
END
ELSE
BEGIN
    PRINT 'Full-text catalog [FTC_AdventureWorks] already exists.';
END
GO

-- 3) Create the full-text index on [Description] (if not already there)
IF NOT EXISTS (
    SELECT 1
    FROM sys.fulltext_indexes 
    WHERE object_id = OBJECT_ID(N'Production.ProductDescription')
)
BEGIN
    PRINT 'Creating full-text index on Production.ProductDescription(Description)...';
    CREATE FULLTEXT INDEX ON [Production].[ProductDescription]
    (
        [Description] LANGUAGE 1033  -- English
    )
    KEY INDEX [PK_ProductDescription_ProductDescriptionID]  -- existing PK
    ON ([FTC_AdventureWorks])
    WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM);
END
ELSE
BEGIN
    PRINT 'Full-text index on Production.ProductDescription already exists.';
END
GO

-- 4) Verify the FT index definition
SELECT 
    t.name AS TableName,
    i.name AS KeyIndex,
    fc.name AS CatalogName,
    fi.is_enabled,
    fic.column_id,
    c.name AS ColumnName,
    fic.language_id
FROM sys.fulltext_indexes AS fi
JOIN sys.objects AS t ON fi.object_id = t.object_id
JOIN sys.indexes AS i ON fi.unique_index_id = i.index_id AND i.object_id = t.object_id
JOIN sys.fulltext_catalogs AS fc ON fi.fulltext_catalog_id = fc.fulltext_catalog_id
JOIN sys.fulltext_index_columns AS fic ON fi.object_id = fic.object_id
JOIN sys.columns AS c ON fic.object_id = c.object_id AND fic.column_id = c.column_id
WHERE t.object_id = OBJECT_ID(N'Production.ProductDescription');
GO