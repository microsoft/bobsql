SET NOCOUNT ON;

-- 1. Row counts: total notes vs embedded, and any NULL/missing embeddings
DECLARE @notes INT      = (SELECT COUNT(*) FROM clinical.ClinicalNote);
DECLARE @embedded INT   = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings);
DECLARE @nullEmb INT    = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings WHERE Embedding IS NULL);
DECLARE @missing INT    = (SELECT COUNT(*) FROM clinical.ClinicalNote n
                           WHERE NOT EXISTS (SELECT 1 FROM clinical.ClinicalNoteEmbeddings e WHERE e.NoteId = n.NoteId));
PRINT CONCAT('NOTES=', @notes, '  EMBEDDED=', @embedded, '  NULL_EMB=', @nullEmb, '  MISSING=', @missing);

-- 2. Vector index present?
SELECT i.name AS index_name, i.type_desc
FROM sys.indexes i
WHERE i.name = 'VIX_ClinicalNoteEmbeddings_Embedding';

-- 3. Prove a stored vector is real: byte length (3072 dims x float16 = 6144 bytes)
SELECT TOP (1)
    NoteId,
    DATALENGTH(Embedding) AS embedding_bytes
FROM clinical.ClinicalNoteEmbeddings
WHERE Embedding IS NOT NULL;
