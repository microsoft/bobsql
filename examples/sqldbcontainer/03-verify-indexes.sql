USE CustomerServiceDesk;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

IF OBJECT_ID(N'dbo.IndexCapabilityProbe', N'U') IS NOT NULL
    THROW 51010, 'IndexCapabilityProbe already exists; nothing replaced.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_configurations
               WHERE name = N'PREVIEW_FEATURES' AND value = 1)
    THROW 51010, 'Run 01-create-database.sql to enable PREVIEW_FEATURES first.', 1;

DECLARE @Created bit = 0;
BEGIN TRY
    CREATE TABLE dbo.IndexCapabilityProbe
    (
        ID int NOT NULL PRIMARY KEY CLUSTERED,
        Category varchar(10) NOT NULL,
        Details json NOT NULL,
        Embedding vector(3) NOT NULL
    );
    SET @Created = 1;

    -- Deterministic engine fixtures, not semantic embeddings.
    INSERT dbo.IndexCapabilityProbe (ID, Category, Details, Embedding)
    SELECT value, CASE WHEN value % 100 = 0 THEN 'rare' ELSE 'web' END,
        CONCAT('{"channel":"', CASE WHEN value % 100 = 0 THEN 'rare' ELSE 'web' END,
               '","case":', value, '}'),
        CAST(JSON_ARRAY(COS(value * 0.01), SIN(value * 0.01), value * 0.001) AS vector(3))
    FROM GENERATE_SERIES(1, 1000);

    CREATE JSON INDEX IX_IndexCapabilityProbe_Details
        ON dbo.IndexCapabilityProbe (Details);
    CREATE VECTOR INDEX IX_IndexCapabilityProbe_Embedding
        ON dbo.IndexCapabilityProbe (Embedding)
        WITH (METRIC = 'cosine', TYPE = 'DiskANN');

    DECLARE @Version int;
    SELECT @Version = TRY_CONVERT(int, JSON_VALUE(build_parameters, '$.Version'))
    FROM sys.vector_indexes
    WHERE object_id = OBJECT_ID(N'dbo.IndexCapabilityProbe')
      AND name = N'IX_IndexCapabilityProbe_Embedding';
    IF @Version IS NULL OR @Version < 3
        THROW 51010, 'The vector index is not the current version 3 or later format.', 1;

    DECLARE @Json TABLE (ID int);
    DECLARE @Ann TABLE (ID int, Distance float);
    DECLARE @Filtered TABLE (ID int, Distance float);
    DECLARE @Exact TABLE (ID int);
    DECLARE @q vector(3);
    SELECT @q = Embedding FROM dbo.IndexCapabilityProbe WHERE ID = 100;
    INSERT @Exact
        SELECT TOP (10) ID FROM dbo.IndexCapabilityProbe
        ORDER BY VECTOR_DISTANCE('cosine', @q, Embedding), ID;

    -- Separate cached statements make index selection independently inspectable.
    INSERT @Json EXEC sys.sp_executesql N'/* sqldbcontainer:json-index */
        SELECT ID FROM dbo.IndexCapabilityProbe
        WHERE JSON_VALUE(Details, ''$.channel'') = ''rare'';';
    INSERT @Ann EXEC sys.sp_executesql N'/* sqldbcontainer:diskann-forced */
        DECLARE @q vector(3);
        SELECT @q = Embedding FROM dbo.IndexCapabilityProbe WHERE ID = 100;
        SELECT TOP (10) WITH APPROXIMATE t.ID, s.distance
        FROM VECTOR_SEARCH(TABLE = dbo.IndexCapabilityProbe AS t,
            COLUMN = Embedding, SIMILAR_TO = @q, METRIC = ''cosine'') AS s
            WITH (FORCE_ANN_ONLY)
        ORDER BY s.distance;';
    INSERT @Filtered EXEC sys.sp_executesql N'/* sqldbcontainer:diskann-filter-forced */
        DECLARE @q vector(3);
        SELECT @q = Embedding FROM dbo.IndexCapabilityProbe WHERE ID = 100;
        SELECT TOP (5) WITH APPROXIMATE t.ID, s.distance
        FROM VECTOR_SEARCH(TABLE = dbo.IndexCapabilityProbe AS t,
            COLUMN = Embedding, SIMILAR_TO = @q, METRIC = ''cosine'') AS s
            WITH (FORCE_ANN_ONLY)
        WHERE t.Category = ''rare''
        ORDER BY s.distance;';

    DECLARE @Overlap int;
    SELECT @Overlap = COUNT(*) FROM @Ann AS a INNER JOIN @Exact AS e ON a.ID = e.ID;
    IF (SELECT COUNT(*) FROM @Json) <> 10
        THROW 51010, 'JSON filtering did not return ten rare cases.', 1;
    IF (SELECT COUNT(*) FROM @Ann) <> 10 OR @Overlap < 9
        THROW 51010, 'ANN returned fewer than ten rows or recall@10 below 0.9 on the fixture.', 1;
    IF (SELECT COUNT(*) FROM @Filtered) <> 5 OR EXISTS
        (SELECT 1 FROM @Filtered AS f INNER JOIN dbo.IndexCapabilityProbe AS t
         ON t.ID = f.ID WHERE t.Category <> 'rare')
        THROW 51010, 'Iterative filtering did not return five qualifying rows.', 1;

    DECLARE @JsonPlan bit = 0, @AnnPlan bit = 0, @FilterPlan bit = 0;
    ;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS p)
    SELECT
        @JsonPlan = CONVERT(bit, MAX(CASE WHEN st.text LIKE N'/* sqldbcontainer:json-index */%'
            AND qp.query_plan.exist('//p:Object[@Index="[IX_IndexCapabilityProbe_Details]"]') = 1
            THEN 1 ELSE 0 END)),
        @AnnPlan = CONVERT(bit, MAX(CASE WHEN st.text LIKE N'/* sqldbcontainer:diskann-forced */%'
            AND qp.query_plan.exist('//p:RelOp[@PhysicalOp="Vector Index Seek"]/*/p:Object[@Index="[IX_IndexCapabilityProbe_Embedding]"]') = 1
            THEN 1 ELSE 0 END)),
        @FilterPlan = CONVERT(bit, MAX(CASE WHEN st.text LIKE N'/* sqldbcontainer:diskann-filter-forced */%'
            AND qp.query_plan.exist('//p:RelOp[@PhysicalOp="Vector Index Seek"]/*/p:Object[@Index="[IX_IndexCapabilityProbe_Embedding]"]') = 1
            THEN 1 ELSE 0 END))
    FROM sys.dm_exec_cached_plans AS cp
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
    CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
    WHERE st.text LIKE N'/* sqldbcontainer:json-index */%'
       OR st.text LIKE N'/* sqldbcontainer:diskann-forced */%'
       OR st.text LIKE N'/* sqldbcontainer:diskann-filter-forced */%';
    IF ISNULL(@JsonPlan, 0) <> 1 OR ISNULL(@AnnPlan, 0) <> 1 OR ISNULL(@FilterPlan, 0) <> 1
        THROW 51010, 'Cached plans did not prove JSON index and both Vector Index Seek paths.', 1;

    DECLARE @Hits TABLE (ID int, Distance float);
    DECLARE @Phase int = 1;
    SET @q = '[1,0,0]';
    WHILE @Phase <= 4
    BEGIN
        IF @Phase = 1
            INSERT dbo.IndexCapabilityProbe VALUES (1001, 'dml', '{"channel":"dml"}', '[1,0,0]');
        IF @Phase = 2
        BEGIN
            UPDATE dbo.IndexCapabilityProbe
            SET Embedding = '[-1,0,0]', Details = '{"channel":"updated"}'
            WHERE ID = 1001;
            INSERT dbo.IndexCapabilityProbe VALUES (1002, 'dml', '{"channel":"dml"}', '[1,0,0]');
        END;
        IF @Phase = 3
            DELETE FROM dbo.IndexCapabilityProbe WHERE ID = 1002;
        IF @Phase = 4
            MERGE dbo.IndexCapabilityProbe AS t USING (SELECT 1003 AS ID) AS s ON t.ID = s.ID
            WHEN NOT MATCHED THEN INSERT (ID, Category, Details, Embedding)
                VALUES (s.ID, 'dml', '{"channel":"merge"}', '[1,0,0]');

        DELETE FROM @Hits;
        INSERT @Hits
            SELECT TOP (5) WITH APPROXIMATE t.ID, s.distance
            FROM VECTOR_SEARCH(TABLE = dbo.IndexCapabilityProbe AS t,
                COLUMN = Embedding, SIMILAR_TO = @q, METRIC = 'cosine') AS s
                WITH (FORCE_ANN_ONLY)
            ORDER BY s.distance;
        IF @Phase = 1 AND NOT EXISTS (SELECT 1 FROM @Hits WHERE ID = 1001 AND ABS(Distance) < 0.000001)
            THROW 51011, 'INSERT missing from ANN results.', 1;
        IF @Phase = 2 AND
            (NOT EXISTS (SELECT 1 FROM @Hits WHERE ID = 1002 AND ABS(Distance) < 0.000001)
             OR EXISTS (SELECT 1 FROM @Hits WHERE ID = 1001))
            THROW 51011, 'UPDATE missing from ANN results.', 1;
        IF @Phase = 3 AND EXISTS (SELECT 1 FROM @Hits WHERE ID = 1002)
            THROW 51011, 'DELETE missing from ANN results.', 1;
        IF @Phase = 4 AND NOT EXISTS (SELECT 1 FROM @Hits WHERE ID = 1003 AND ABS(Distance) < 0.000001)
            THROW 51011, 'MERGE missing from ANN results.', 1;
        SET @Phase += 1;
    END;
    IF (SELECT COUNT(*) FROM dbo.IndexCapabilityProbe
        WHERE JSON_VALUE(Details, '$.channel') = 'updated') <> 1
        THROW 51012, 'Updated JSON filter is incorrect.', 1;

    DROP TABLE dbo.IndexCapabilityProbe;
    SET @Created = 0;
    SELECT 'JSON index' AS Test, 'PASS' AS Result, 'Index seek; 10 matching rows; update visible' AS Evidence
    UNION ALL SELECT 'DiskANN', 'PASS', CONCAT('Version ', @Version, '; Vector Index Seek; recall@10 ', @Overlap, '/10')
    UNION ALL SELECT 'Iterative filtering', 'PASS', 'Vector Index Seek; 5/5 rows match rare category'
    UNION ALL SELECT 'Index maintenance', 'PASS', 'INSERT, UPDATE, DELETE, MERGE reflected in forced ANN searches';
END TRY
BEGIN CATCH
    IF @Created = 1
        DROP TABLE dbo.IndexCapabilityProbe;
    THROW;
END CATCH;
