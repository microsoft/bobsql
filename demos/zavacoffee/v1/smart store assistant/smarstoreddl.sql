/* ========================================================================
   ZAVA COFFEE – Store Edge Schema (SQL Server 2025)
   Purpose  : On-prem, AI-only stores (HPE edge) with local vector search
/* If you plan to use the VECTOR_SEARCH() T‑SQL function during preview,
   it may require server-level trace flags (admin choice). Not needed to
   create the schema itself. See docs for current requirements. */

/* Sensible session options */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------------------
   1) Schemas
   ------------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sec')    EXEC('CREATE SCHEMA sec');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'doc')    EXEC('CREATE SCHEMA doc');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'assist') EXEC('CREATE SCHEMA assist');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sync')   EXEC('CREATE SCHEMA sync');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'qa')     EXEC('CREATE SCHEMA qa');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'kg')     EXEC('CREATE SCHEMA kg');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ai')     EXEC('CREATE SCHEMA ai');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ops')    EXEC('CREATE SCHEMA ops');
GO

/* ------------------------------------------------------------------------
   2) OPS (stores/devices)
   ------------------------------------------------------------------------ */
IF OBJECT_ID('ops.Store','U') IS NULL
CREATE TABLE ops.Store
(
  store_id     INT IDENTITY(1,1) PRIMARY KEY,
  store_code   NVARCHAR(20)  NOT NULL UNIQUE,
  store_name   NVARCHAR(100) NOT NULL,
  city         NVARCHAR(80)  NULL,
  timezone     NVARCHAR(64)  NULL,
  active       BIT           NOT NULL DEFAULT (1),
  created_utc  DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('ops.Device','U') IS NULL
CREATE TABLE ops.Device
(
  device_id     INT IDENTITY(1,1) PRIMARY KEY,
  device_code   NVARCHAR(50) NOT NULL UNIQUE,
  device_type   NVARCHAR(20) NOT NULL CHECK (device_type IN ('POS','KIOSK','BACKOFFICE')),
  store_id      INT NOT NULL,
  version_tag   NVARCHAR(40) NULL,
  last_seen_utc DATETIME2(0) NULL,
  active        BIT NOT NULL DEFAULT (1),
  CONSTRAINT FK_Device_Store FOREIGN KEY(store_id) REFERENCES ops.Store(store_id)
);

IF OBJECT_ID('ops.AgentHeartbeat','U') IS NULL
CREATE TABLE ops.AgentHeartbeat
(
  hb_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
  device_id    INT NOT NULL,
  agent_version NVARCHAR(40) NOT NULL,
  status       NVARCHAR(20) NOT NULL,   -- OK/DEGRADED/ERROR
  msg          NVARCHAR(200) NULL,
  seen_utc     DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT FK_HB_Device FOREIGN KEY(device_id) REFERENCES ops.Device(device_id)
);
GO

/* ------------------------------------------------------------------------
   3) SECURITY (principals + store-role mapping) & RLS helpers
   ------------------------------------------------------------------------ */
IF OBJECT_ID('sec.UserPrincipal','U') IS NULL
CREATE TABLE sec.UserPrincipal
(
  user_id      INT IDENTITY(1,1) PRIMARY KEY,
  login_name   NVARCHAR(256) NOT NULL UNIQUE,  -- maps to SUSER_SNAME() or app user
  display_name NVARCHAR(100) NULL,
  created_utc  DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('sec.UserStoreRole','U') IS NULL
CREATE TABLE sec.UserStoreRole
(
  user_id   INT NOT NULL,
  store_id  INT NOT NULL,
  role_name NVARCHAR(40) NOT NULL,      -- BARISTA/MANAGER/TECH/...
  PRIMARY KEY(user_id, store_id, role_name),
  CONSTRAINT FK_USR_User  FOREIGN KEY(user_id)  REFERENCES sec.UserPrincipal(user_id),
  CONSTRAINT FK_USR_Store FOREIGN KEY(store_id) REFERENCES ops.Store(store_id)
);
GO

/* Inline TVF: allow rows when (a) global (NULL scope),
   (b) SESSION_CONTEXT('store_id') matches, or
   (c) SUSER_SNAME() is mapped to the scoped store via sec.UserStoreRole */
IF OBJECT_ID('sec.fn_rls_can_read_doc','IF') IS NOT NULL DROP FUNCTION sec.fn_rls_can_read_doc;
GO
CREATE FUNCTION sec.fn_rls_can_read_doc (@store_scope INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS allow  WHERE @store_scope IS NULL
    UNION ALL
    SELECT 1 WHERE @store_scope IS NOT NULL
              AND TRY_CAST(SESSION_CONTEXT(N'store_id') AS INT) = @store_scope
    UNION ALL
    SELECT 1
    FROM sec.UserPrincipal up
    JOIN sec.UserStoreRole  ur ON ur.user_id = up.user_id
    WHERE up.login_name = SUSER_SNAME()
      AND ur.store_id   = @store_scope
);
GO

/* ------------------------------------------------------------------------
   4) DOCUMENTS (temporal) + CHUNKS (temporal) + EMBEDDINGS (vector)
   ------------------------------------------------------------------------ */

IF OBJECT_ID('doc.Document','U') IS NULL
BEGIN
  CREATE TABLE doc.Document
  (
    doc_id        BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    title         NVARCHAR(400) NOT NULL,
    locale        NVARCHAR(10)  NOT NULL,  -- e.g., en-US
    store_scope   INT NULL,                -- NULL = global; else store_id
    version_label NVARCHAR(40)  NOT NULL,  -- e.g., v2.1
    status        NVARCHAR(20)  NOT NULL,  -- Draft/Approved/Published
    category      NVARCHAR(60)  NULL,      -- SOP/Recipe/Policy/Manual
    created_by    NVARCHAR(256) NULL,

    ValidFrom     DATETIME2 GENERATED ALWAYS AS ROW START,
    ValidTo       DATETIME2 GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),

    CONSTRAINT FK_Doc_StoreScope FOREIGN KEY(store_scope) REFERENCES ops.Store(store_id)
  )
  WITH ( SYSTEM_VERSIONING = ON (HISTORY_TABLE = doc.Document_History) );
END
GO

IF OBJECT_ID('doc.DocumentChunk','U') IS NULL
BEGIN
  CREATE TABLE doc.DocumentChunk
  (
    doc_id     BIGINT NOT NULL,
    chunk_no   INT    NOT NULL,
    text_hash  BINARY(32) NOT NULL,
    source_uri NVARCHAR(400) NULL,
    chunk_text NVARCHAR(MAX) NOT NULL,

    ValidFrom  DATETIME2 GENERATED ALWAYS AS ROW START,
    ValidTo    DATETIME2 GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),

    CONSTRAINT PK_DocChunk PRIMARY KEY (doc_id, chunk_no),
    CONSTRAINT FK_DocChunk_Doc FOREIGN KEY (doc_id) REFERENCES doc.Document(doc_id)
  )
  WITH ( SYSTEM_VERSIONING = ON (HISTORY_TABLE = doc.DocumentChunk_History) );
END
GO

IF OBJECT_ID('doc.DocumentEmbedding','U') IS NULL
CREATE TABLE doc.DocumentEmbedding
(
  doc_id       BIGINT    NOT NULL,
  chunk_no     INT       NOT NULL,
  model_id     INT       NOT NULL,
  dims         SMALLINT  NOT NULL,            -- e.g., 768
  precision    VARCHAR(8) NOT NULL,           -- 'float32' | 'float16' (preview)
  embedding    VECTOR(768) NOT NULL,          -- adjust to your model dims
  created_utc  DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY (doc_id, chunk_no, model_id),
  CONSTRAINT FK_DocEmb_Chunk FOREIGN KEY (doc_id, chunk_no)
    REFERENCES doc.DocumentChunk(doc_id, chunk_no)
);
GO

/* Vector ANN index (DiskANN) – fast approximate similarity search (preview) */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DocEmb_ANN' AND object_id = OBJECT_ID('doc.DocumentEmbedding'))
    DROP INDEX IF EXISTS IX_DocEmb_ANN ON doc.DocumentEmbedding;
GO
CREATE VECTOR INDEX IX_DocEmb_ANN
ON doc.DocumentEmbedding(embedding)
USING DISKANN WITH (METRIC = 'cosine');  -- choose 'cosine' | 'dot' | 'euclidean'
GO
/* Vector type & vector indexes are part of SQL Server 2025 preview. */ 

/* ------------------------------------------------------------------------
   5) RLS policies over docs, chunks, embeddings
   ------------------------------------------------------------------------ */

/* Document policy (store-scoped or global) */
IF OBJECT_ID('sec.Policy_Document_RLS','SP') IS NOT NULL
  DROP SECURITY POLICY sec.Policy_Document_RLS;
GO
CREATE SECURITY POLICY sec.Policy_Document_RLS
ADD FILTER PREDICATE sec.fn_rls_can_read_doc(store_scope) ON doc.Document
WITH (STATE = ON);
GO

/* Chunk policy – consult parent doc scope via TVF */
IF OBJECT_ID('sec.fn_rls_can_read_chunk','IF') IS NOT NULL DROP FUNCTION sec.fn_rls_can_read_chunk;
GO
CREATE FUNCTION sec.fn_rls_can_read_chunk (@doc_id BIGINT)
RETURNS TABLE WITH SCHEMABINDING
AS
RETURN
(
  SELECT 1
  FROM doc.Document d
  WHERE d.doc_id = @doc_id
    AND EXISTS (SELECT 1 FROM sec.fn_rls_can_read_doc(d.store_scope))
);
GO

IF OBJECT_ID('sec.Policy_DocChunk_RLS','SP') IS NOT NULL
  DROP SECURITY POLICY sec.Policy_DocChunk_RLS;
GO
CREATE SECURITY POLICY sec.Policy_DocChunk_RLS
ADD FILTER PREDICATE sec.fn_rls_can_read_chunk(doc_id) ON doc.DocumentChunk
WITH (STATE = ON);
GO

/* Embedding policy – reference chunk/doc scope */
IF OBJECT_ID('sec.fn_rls_can_read_embedding','IF') IS NOT NULL DROP FUNCTION sec.fn_rls_can_read_embedding;
GO
CREATE FUNCTION sec.fn_rls_can_read_embedding(@doc_id BIGINT, @chunk_no INT)
RETURNS TABLE WITH SCHEMABINDING
AS
RETURN
(
  SELECT 1
  FROM doc.DocumentChunk dc
  WHERE dc.doc_id = @doc_id AND dc.chunk_no = @chunk_no
    AND EXISTS (SELECT 1 FROM sec.fn_rls_can_read_chunk(@doc_id))
);
GO

IF OBJECT_ID('sec.Policy_Embedding_RLS','SP') IS NOT NULL
  DROP SECURITY POLICY sec.Policy_Embedding_RLS;
GO
CREATE SECURITY POLICY sec.Policy_Embedding_RLS
ADD FILTER PREDICATE sec.fn_rls_can_read_embedding(doc_id, chunk_no) ON doc.DocumentEmbedding
WITH (STATE = ON);
GO

/* ------------------------------------------------------------------------
   6) ASSIST (query/feedback logs) – for offline batch sync to HQ
   ------------------------------------------------------------------------ */
IF OBJECT_ID('assist.QueryLog','U') IS NULL
CREATE TABLE assist.QueryLog
(
  query_id    BIGINT IDENTITY(1,1) PRIMARY KEY,
  user_login  NVARCHAR(256) NOT NULL DEFAULT SUSER_SNAME(),
  store_id    INT NULL,
  query_text  NVARCHAR(2000) NOT NULL,
  asked_utc   DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  channel     NVARCHAR(20) NULL,    -- POS/KIOSK/BACKOFFICE
  app_version NVARCHAR(40) NULL
);
CREATE INDEX IX_QueryLog_StoreTime ON assist.QueryLog(store_id, asked_utc);

IF OBJECT_ID('assist.RetrievalLog','U') IS NULL
CREATE TABLE assist.RetrievalLog
(
  retrieval_id BIGINT IDENTITY(1,1) PRIMARY KEY,
  query_id     BIGINT NOT NULL,
  doc_id       BIGINT NOT NULL,
  chunk_no     INT NOT NULL,
  distance     REAL NOT NULL,       -- vector distance
  rank_no      INT  NOT NULL,
  pipeline_ver NVARCHAR(20) NULL,
  CONSTRAINT FK_RL_Q  FOREIGN KEY(query_id)        REFERENCES assist.QueryLog(query_id),
  CONSTRAINT FK_RL_CK FOREIGN KEY(doc_id, chunk_no) REFERENCES doc.DocumentChunk(doc_id, chunk_no)
);

IF OBJECT_ID('assist.AnswerFeedback','U') IS NULL
CREATE TABLE assist.AnswerFeedback
(
  feedback_id BIGINT IDENTITY(1,1) PRIMARY KEY,
  query_id    BIGINT  NOT NULL,
  rating      TINYINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comments    NVARCHAR(500) NULL,
  created_utc DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT FK_FB_Q FOREIGN KEY(query_id) REFERENCES assist.QueryLog(query_id)
);
GO

/* ------------------------------------------------------------------------
   7) QA (regex rules & findings) – enforcement happens in jobs/app
   ------------------------------------------------------------------------ */
IF OBJECT_ID('qa.ValidationRule','U') IS NULL
CREATE TABLE qa.ValidationRule
(
  rule_id     INT IDENTITY(1,1) PRIMARY KEY,
  name        NVARCHAR(100) NOT NULL,
  applies_to  NVARCHAR(20)  NOT NULL,   -- HEADER/CHUNK
  field_name  NVARCHAR(40)  NULL,       -- e.g., 'chunk_text'
  regex       NVARCHAR(400) NOT NULL,   -- for REGEXP_* functions (preview)
  severity    NVARCHAR(10)  NOT NULL,   -- INFO/WARN/ERROR
  description NVARCHAR(200) NULL,
  active      BIT NOT NULL DEFAULT (1)
);

IF OBJECT_ID('qa.ValidationFinding','U') IS NULL
CREATE TABLE qa.ValidationFinding
(
  finding_id BIGINT IDENTITY(1,1) PRIMARY KEY,
  rule_id    INT     NOT NULL,
  doc_id     BIGINT  NOT NULL,
  chunk_no   INT     NULL,
  location   NVARCHAR(80)  NULL,
  excerpt    NVARCHAR(200) NULL,
  found_utc  DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT FK_VF_R  FOREIGN KEY(rule_id)           REFERENCES qa.ValidationRule(rule_id),
  CONSTRAINT FK_VF_CK FOREIGN KEY(doc_id, chunk_no)  REFERENCES doc.DocumentChunk(doc_id, chunk_no)
);
GO

/* ------------------------------------------------------------------------
   8) AI (model registry, embedding jobs, index build logs)
   ------------------------------------------------------------------------ */
IF OBJECT_ID('ai.Model','U') IS NULL
CREATE TABLE ai.Model
(
  model_id    INT IDENTITY(1,1) PRIMARY KEY,
  name        NVARCHAR(100) NOT NULL,       -- 'nomic-embed-text' (Ollama) / HF id
  provider    NVARCHAR(60)  NOT NULL,       -- 'Ollama','vLLM','Local'
  dims        SMALLINT      NOT NULL,
  precision   VARCHAR(8)    NOT NULL,       -- 'float32' | 'float16'
  license_url NVARCHAR(400) NULL,
  active      BIT           NOT NULL DEFAULT (1),
  created_utc DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('ai.EmbeddingJob','U') IS NULL
CREATE TABLE ai.EmbeddingJob
(
  job_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
  model_id    INT NOT NULL,
  doc_id      BIGINT NOT NULL,
  started_utc DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  finished_utc DATETIME2(0) NULL,
  status      NVARCHAR(20) NOT NULL DEFAULT 'RUNNING', -- RUNNING/OK/FAILED
  details     NVARCHAR(400) NULL,
  CONSTRAINT FK_EJ_Model FOREIGN KEY(model_id) REFERENCES ai.Model(model_id),
  CONSTRAINT FK_EJ_Doc   FOREIGN KEY(doc_id)   REFERENCES doc.Document(doc_id)
);

IF OBJECT_ID('ai.VectorIndexBuild','U') IS NULL
CREATE TABLE ai.VectorIndexBuild
(
  build_id    BIGINT IDENTITY(1,1) PRIMARY KEY,
  table_name  SYSNAME NOT NULL,
  column_name SYSNAME NOT NULL,
  metric      NVARCHAR(20) NOT NULL,      -- cosine/dot/euclidean
  params_json NVARCHAR(MAX) NULL,
  built_utc   DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
  notes       NVARCHAR(400) NULL
);
GO

/* ------------------------------------------------------------------------
   9) SYNC (offline-friendly change tracking & packages)
   ------------------------------------------------------------------------ */
IF OBJECT_ID('sync.ChangeLog','U') IS NULL
CREATE TABLE sync.ChangeLog
(
  change_id   BIGINT IDENTITY(1,1) PRIMARY KEY,
  entity_type NVARCHAR(40) NOT NULL,    -- 'Document','Chunk','Embedding','QueryLog', ...
  entity_key  NVARCHAR(200) NOT NULL,   -- e.g., 'doc_id=123|chunk_no=2'
  op          CHAR(1) NOT NULL,         -- I/U/D
  payload     NVARCHAR(MAX) NULL,       -- optional compact JSON
  ts_utc      DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  sent_utc    DATETIME2(0) NULL
);

IF OBJECT_ID('sync.SyncStatus','U') IS NULL
CREATE TABLE sync.SyncStatus
(
  sync_id     INT IDENTITY(1,1) PRIMARY KEY,
  target_name NVARCHAR(100) NOT NULL,   -- 'HQ'
  table_name  SYSNAME       NOT NULL,
  last_ts_utc DATETIME2(0)  NULL,
  last_row_id BIGINT        NULL,
  notes       NVARCHAR(200) NULL,
  UNIQUE (target_name, table_name)
);

IF OBJECT_ID('sync.Package','U') IS NULL
CREATE TABLE sync.Package
(
  package_id  BIGINT IDENTITY(1,1) PRIMARY KEY,
  package_tag NVARCHAR(60) NOT NULL UNIQUE,
  created_utc DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  created_by  NVARCHAR(256) NULL,
  notes       NVARCHAR(400) NULL
);

IF OBJECT_ID('sync.PackageItem','U') IS NULL
CREATE TABLE sync.PackageItem
(
  package_id BIGINT NOT NULL,
  entity_type NVARCHAR(40) NOT NULL,    -- 'Document','Model'
  entity_id   NVARCHAR(60)  NOT NULL,
  PRIMARY KEY(package_id, entity_type, entity_id),
  CONSTRAINT FK_PkgItem_Pkg FOREIGN KEY(package_id) REFERENCES sync.Package(package_id)
);
GO

/* ------------------------------------------------------------------------
   10) GRAPH (optional) – Concepts & relationships
   ------------------------------------------------------------------------ */
IF OBJECT_ID('kg.Concept','U') IS NULL
EXEC('CREATE TABLE kg.Concept (concept_id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(120) NOT NULL, kind NVARCHAR(40) NOT NULL) AS NODE;');

IF OBJECT_ID('kg.RelatesTo','U') IS NULL
EXEC('CREATE TABLE kg.RelatesTo (rel_type NVARCHAR(40) NULL, weight FLOAT NULL) AS EDGE;');

IF OBJECT_ID('kg.ConceptDocument','U') IS NULL
CREATE TABLE kg.ConceptDocument
(
  concept_id INT    NOT NULL,
  doc_id     BIGINT NOT NULL,
  PRIMARY KEY (concept_id, doc_id),
  CONSTRAINT FK_CD_Concept FOREIGN KEY(concept_id) REFERENCES kg.Concept(concept_id),
  CONSTRAINT FK_CD_Doc     FOREIGN KEY(doc_id)     REFERENCES doc.Document(doc_id)
);
GO

/* ------------------------------------------------------------------------
   11) Helpful indexes
   ------------------------------------------------------------------------ */
CREATE INDEX IX_Doc_Store_Status ON doc.Document(store_scope, status) WHERE status = 'Published';
CREATE INDEX IX_DocChunk_Doc       ON doc.DocumentChunk(doc_id, chunk_no);
CREATE INDEX IX_Emb_Model          ON doc.DocumentEmbedding(model_id, doc_id, chunk_no)
                                    INCLUDE (dims, precision, created_utc);
CREATE INDEX IX_FB_Query           ON assist.AnswerFeedback(query_id);
GO

/* ------------------------------------------------------------------------
   12) Final sanity
   ------------------------------------------------------------------------ */
PRINT '✅ Zava Edge schema deployed (vectors, temporal, RLS, sync, QA, graph).';
   Features : VECTOR(n) + DiskANN, Temporal History, Row-Level Security,
              Offline-friendly sync, QA (regex), optional SQL Graph
   ======================================================================== */

SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------------
   0) Enable preview features (required for vectors & DiskANN)
   ------------------------------------------------------------------------ */
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO
