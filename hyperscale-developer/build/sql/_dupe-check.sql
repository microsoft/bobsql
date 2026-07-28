SET NOCOUNT ON;

/* 1. Overall duplication (hash NoteText — it is < 8KB) */
WITH h AS (
    SELECT HASHBYTES('SHA2_256', NoteText) AS nh
    FROM clinical.ClinicalNote
)
SELECT
    COUNT(*)                              AS total_notes,
    COUNT(DISTINCT nh)                    AS distinct_notes,
    COUNT(*) - COUNT(DISTINCT nh)         AS duplicate_rows,
    CAST(100.0 * (COUNT(*) - COUNT(DISTINCT nh)) / COUNT(*) AS DECIMAL(5,2)) AS pct_duplicated
FROM h;
GO

/* 2. Worst offenders — how many copies of the most-repeated notes */
SELECT TOP 15
    COUNT(*)               AS copies,
    MIN(EncounterId)       AS example_encounter,
    LEFT(MIN(NoteText), 70) AS sample
FROM clinical.ClinicalNote
GROUP BY HASHBYTES('SHA2_256', NoteText)
ORDER BY COUNT(*) DESC;
GO

/* 3. Distinct CreatedAt values (are timestamps all identical too?) */
SELECT
    COUNT(*)                       AS total_notes,
    COUNT(DISTINCT CreatedAt)      AS distinct_created_at,
    MIN(CreatedAt)                 AS min_created,
    MAX(CreatedAt)                 AS max_created
FROM clinical.ClinicalNote;
GO
