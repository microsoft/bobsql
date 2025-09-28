/* ========================================================================
   ZAVA COFFEE – Store Edge Seed Data (SQL Server 2025)
   Prereq: The full schema from earlier is deployed in this database.
   This script:
     - Inserts sample stores, user, device
     - Adds an embedding model
     - Seeds 2 documents + chunks + 768-dim embeddings
     - Adds basic QA rule & sample feedback
     - Runs a smoke test (exact KNN) and an RLS check
   ======================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ------------------------------------------------------------------------
   0) Helper: create a 768-dim JSON vector deterministically
      - Builds values in [-0.1..0.1] using SIN(); adjust if desired.
      - Returns NVARCHAR(MAX) JSON array string '[x1, x2, ... x768]'
   ------------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#seed_dims') IS NOT NULL DROP TABLE #seed_dims;
CREATE TABLE #seed_dims (dim INT PRIMARY KEY);

;WITH n AS (
  SELECT 1 AS i
  UNION ALL SELECT i+1 FROM n WHERE i < 768
)
INSERT #seed_dims(dim) SELECT i FROM n OPTION (MAXRECURSION 0);

DECLARE @json_vec_768 NVARCHAR(MAX);
SELECT @json_vec_768 =
  '[' + STRING_AGG(CONVERT(NVARCHAR(32),
          CONVERT(DECIMAL(10,6), SIN(dim*1.0)/10.0)), ',') + ']'
FROM #seed_dims;

-- You can reuse @json_vec_768 for any 768-dim embedding insert.

/* ------------------------------------------------------------------------
   1) Seed OPS: Stores, Device
   ------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM ops.Store WHERE store_code = N'DAL-01')
INSERT ops.Store(store_code, store_name, city, timezone)
VALUES (N'DAL-01', N'Zava Dallas Downtown', N'Dallas', N'Central Standard Time');

IF NOT EXISTS (SELECT 1 FROM ops.Store WHERE store_code = N'SEA-01')
INSERT ops.Store(store_code, store_name, city, timezone)
VALUES (N'SEA-01', N'Zava Seattle Ballard', N'Seattle', N'Pacific Standard Time');

DECLARE @store_dal INT = (SELECT store_id FROM ops.Store WHERE store_code = N'DAL-01');
DECLARE @store_sea INT = (SELECT store_id FROM ops.Store WHERE store_code = N'SEA-01');

IF NOT EXISTS (SELECT 1 FROM ops.Device WHERE device_code = N'POS-DAL-01')
INSERT ops.Device(device_code, device_type, store_id, version_tag)
VALUES (N'POS-DAL-01', N'POS', @store_dal, N'edge-1.0');

/* ------------------------------------------------------------------------
   2) Seed SEC: Principal + Store role
   ------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sec.UserPrincipal WHERE login_name = SUSER_SNAME())
BEGIN
  INSERT sec.UserPrincipal(login_name, display_name)
  VALUES (SUSER_SNAME(), N'Local Admin');
END;

IF NOT EXISTS (
    SELECT 1 FROM sec.UserStoreRole ur
    JOIN sec.UserPrincipal up ON up.user_id = ur.user_id
    WHERE up.login_name = SUSER_SNAME() AND ur.store_id = @store_dal
)
INSERT sec.UserStoreRole(user_id, store_id, role_name)
SELECT up.user_id, @store_dal, N'MANAGER'
FROM sec.UserPrincipal up
WHERE up.login_name = SUSER_SNAME();

/* ------------------------------------------------------------------------
   3) Seed AI: Embedding model registry (768-dim)
   ------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM ai.Model WHERE name = N'nomic-embed-text')
INSERT ai.Model(name, provider, dims, precision, license_url)
VALUES (N'nomic-embed-text', N'Ollama', 768, 'float32',
        N'https://ollama.com/library/nomic-embed-text');

DECLARE @model_id INT = (SELECT model_id FROM ai.Model WHERE name = N'nomic-embed-text');

/* ------------------------------------------------------------------------
   4) Seed DOC: Two documents (one store-scoped, one global) + chunks
   ------------------------------------------------------------------------ */
-- A) Latte SOP (Published) scoped to DAL-01
IF NOT EXISTS (SELECT 1 FROM doc.Document WHERE title = N'Latte SOP')
INSERT doc.Document(title, locale, store_scope, version_label, status, category, created_by)
VALUES (N'Latte SOP', N'en-US', @store_dal, N'v1.0', N'Published', N'SOP', SUSER_SNAME());

DECLARE @doc_latte BIGINT = (SELECT doc_id FROM doc.Document WHERE title = N'Latte SOP');

IF NOT EXISTS (SELECT 1 FROM doc.DocumentChunk WHERE doc_id = @doc_latte AND chunk_no = 1)
INSERT doc.DocumentChunk(doc_id, chunk_no, text_hash, source_uri, chunk_text)
VALUES
(@doc_latte, 1, HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'Latte_SOP_1')),
 N'file:///sops/latte.pdf#1',
 N'For a 16 oz latte: purge steam wand; steam milk to 60–65°C; note dairy allergen. ' +
 N'Wipe and purge wand immediately after use.');

-- B) Grinder Cleaning SOP (Published) – GLOBAL (NULL scope)
IF NOT EXISTS (SELECT 1 FROM doc.Document WHERE title = N'Grinder Cleaning SOP')
INSERT doc.Document(title, locale, store_scope, version_label, status, category, created_by)
VALUES (N'Grinder Cleaning SOP', N'en-US', NULL, N'v1.0', N'Published', N'SOP', SUSER_SNAME());

DECLARE @doc_grinder BIGINT = (SELECT doc_id FROM doc.Document WHERE title = N'Grinder Cleaning SOP');

IF NOT EXISTS (SELECT 1 FROM doc.DocumentChunk WHERE doc_id = @doc_grinder AND chunk_no = 1)
INSERT doc.DocumentChunk(doc_id, chunk_no, text_hash, source_uri, chunk_text)
VALUES
(@doc_grinder, 1, HASHBYTES('SHA2_256', CONVERT(varbinary(max), N'Grinder_SOP_1')),
 N'file:///sops/grinder.pdf#1',
 N'Switch off and unplug grinder. Remove hopper; brush burrs; run cleaning pellets per vendor SOP.');

/* ------------------------------------------------------------------------
   5) Seed EMBEDDINGS: 768-dim vectors for each chunk
      We reuse @json_vec_768 to keep the script compact.
   ------------------------------------------------------------------------ */
-- Latte SOP embedding
IF NOT EXISTS (SELECT 1 FROM doc.DocumentEmbedding WHERE doc_id = @doc_latte AND chunk_no = 1 AND model_id = @model_id)
INSERT doc.DocumentEmbedding(doc_id, chunk_no, model_id, dims, precision, embedding)
VALUES (@doc_latte, 1, @model_id, 768, 'float32', @json_vec_768);

-- Grinder SOP embedding
IF NOT EXISTS (SELECT 1 FROM doc.DocumentEmbedding WHERE doc_id = @doc_grinder AND chunk_no = 1 AND model_id = @model_id)
INSERT doc.DocumentEmbedding(doc_id, chunk_no, model_id, dims, precision, embedding)
VALUES (@doc_grinder, 1, @model_id, 768, 'float32', @json_vec_768);

/* Optional: mark index build log */
INSERT ai.VectorIndexBuild(table_name, column_name, metric, params_json, notes)
VALUES (N'doc.DocumentEmbedding', N'embedding', N'cosine', NULL, N'Initial seed embeddings');

/* ------------------------------------------------------------------------
   6) QA: A simple rule requiring an allergen note in beverage SOP chunks
   ------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM qa.ValidationRule WHERE name = N'Allergen mention in beverage SOP')
INSERT qa.ValidationRule(name, applies_to, field_name, regex, severity, description, active)
VALUES (N'Allergen mention in beverage SOP', N'CHUNK', N'chunk_text',
        N'(?i)\ballergen\b', N'WARN',
        N'Beverage SOP chunks should mention allergen when applicable', 1);

/* ------------------------------------------------------------------------
   7) Sample usage logs & feedback (optional)
   ------------------------------------------------------------------------ */
DECLARE @q BIGINT;
INSERT assist.QueryLog(user_login, store_id, query_text, channel, app_version)
VALUES (SUSER_SNAME(), @store_dal, N'What temperature for a 16 oz latte?', N'BACKOFFICE', N'ui-1.0');
SET @q = SCOPE_IDENTITY();

INSERT assist.RetrievalLog(query_id, doc_id, chunk_no, distance, rank_no, pipeline_ver)
VALUES (@q, @doc_latte, 1, 0.0123, 1, N'p1');

INSERT assist.AnswerFeedback(query_id, rating, comments)
VALUES (@q, 5, N'Clear and correct');

/* ------------------------------------------------------------------------
   8) GRAPH (optional): tie a concept to the Latte SOP
   ------------------------------------------------------------------------ */
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Concept' AND schema_id = SCHEMA_ID(N'kg'))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM kg.Concept WHERE name = N'Latte Preparation')
    INSERT kg.Concept(name, kind) VALUES (N'Latte Preparation', N'Procedure');

  IF NOT EXISTS (
      SELECT 1 FROM kg.ConceptDocument cd
      JOIN kg.Concept c ON c.concept_id = cd.concept_id
      WHERE c.name = N'Latte Preparation' AND cd.doc_id = @doc_latte
  )
    INSERT kg.ConceptDocument(concept_id, doc_id)
    SELECT concept_id, @doc_latte FROM kg.Concept WHERE name = N'Latte Preparation';
END

/* ------------------------------------------------------------------------
   9) Smoke test: exact K‑NN over published docs (no ANN needed)
   ------------------------------------------------------------------------ */
PRINT N'-- Smoke test: exact similarity on published docs (top 3)';
DECLARE @qvec VECTOR(768) = @json_vec_768;  -- reuse seeded vector as a query

SELECT TOP (3)
    d.doc_id, d.title, dc.chunk_no,
    VECTOR_DISTANCE('cosine', de.embedding, @qvec) AS distance
FROM doc.Document d
JOIN doc.DocumentChunk dc ON dc.doc_id = d.doc_id AND dc.chunk_no = 1
JOIN doc.DocumentEmbedding de ON de.doc_id = dc.doc_id AND de.chunk_no = dc.chunk_no
WHERE d.status = 'Published'
ORDER BY distance;

PRINT N'-- If you enabled VECTOR_SEARCH() preview & built DiskANN, you can try ANN separately.';

 /* -----------------------------------------------------------------------
    10) RLS check: only DAL-01 + global should be visible when store_id=DAL
    (Reset or comment this out if your app sets session context itself.)
    ----------------------------------------------------------------------- */
EXEC sys.sp_set_session_context @key='store_id', @value=@store_dal;

PRINT N'-- RLS visibility check (should include Latte SOP and any global docs):';
SELECT d.doc_id, d.title, d.store_scope, d.status
FROM doc.Document AS d
ORDER BY d.title;

-- clear session context
EXEC sys.sp_set_session_context @key='store_id', @value=NULL;
PRINT N'✅ Seed complete.';
GO