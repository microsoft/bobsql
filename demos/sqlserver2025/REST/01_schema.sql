USE MASTER;
GO
IF EXISTS (SELECT * from sys.databases WHERE name = 'zavacliniq')
    ALTER DATABASE zavacliniq SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
DROP DATABASE IF EXISTS zavacliniq;
GO
CREATE DATABASE zavacliniq;
GO

USE zavacliniq;
GO

-- Create an external model
IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'MyOllamaEmbeddingModel')
DROP EXTERNAL MODEL MyOllamaEmbeddingModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyOllamaEmbeddingModel
WITH ( 
      LOCATION = 'https://localhost/api/embed',
      API_FORMAT = 'Ollama',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'mxbai-embed-large');
GO

-- Turn on PREVIEW_SETTINGS to use vector indexing
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

/* ========================================================================== */
/* 1) KNOWLEDGE BASE: documents, chunks, embeddings (NO PHI)                  */
/* ========================================================================== */
IF SCHEMA_ID('content') IS NULL EXEC('CREATE SCHEMA content');
GO

DROP TABLE IF EXISTS content.Document;
GO
CREATE TABLE content.Document (
    DocumentId        BIGINT            IDENTITY PRIMARY KEY,
    ExternalRef       NVARCHAR(200)     NULL,
    Title             NVARCHAR(400)     NOT NULL,
    DocType           NVARCHAR(50)      NOT NULL,  -- SOP | Manual | Policy | Guideline
    Specialty         NVARCHAR(100)     NULL,
    DeviceModel       NVARCHAR(100)     NULL,
    Language          NVARCHAR(10)      NOT NULL DEFAULT (N'en'),
    ClinicScope       NVARCHAR(100)     NULL,
    VersionLabel      NVARCHAR(50)      NULL,
    EffectiveFrom     DATE              NULL,
    EffectiveTo       DATE              NULL,
    IsActive          BIT               NOT NULL DEFAULT (1),
    ContentHash       VARBINARY(32)     NULL,
    CreatedUtc        DATETIME2(3)      NOT NULL DEFAULT (SYSUTCDATETIME()),
    UpdatedUtc        DATETIME2(3)      NOT NULL DEFAULT (SYSUTCDATETIME())
);
GO
CREATE INDEX IX_Document_Filter ON content.Document (IsActive, Language, Specialty, DocType, ClinicScope);
GO

DROP TABLE IF EXISTS content.Chunk;
GO
CREATE TABLE content.Chunk (
    ChunkId           BIGINT            IDENTITY PRIMARY KEY,
    DocumentId        BIGINT            NOT NULL REFERENCES content.Document(DocumentId),
    ChunkOrd          INT               NOT NULL,
    ChunkText         NVARCHAR(MAX)     NOT NULL,
    TokenCount        INT               NULL,
    Language          NVARCHAR(10)      NOT NULL,
    ClinicScope       NVARCHAR(100)     NULL,
    CreatedUtc        DATETIME2(3)      NOT NULL DEFAULT (SYSUTCDATETIME()),
    UpdatedUtc        DATETIME2(3)      NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UX_Chunk_Doc_Ord UNIQUE (DocumentId, ChunkOrd)
);
GO
CREATE INDEX IX_Chunk_Filter ON content.Chunk (Language, ClinicScope);
GO

DROP TABLE IF EXISTS content.ChunkEmbedding;
GO
CREATE TABLE content.ChunkEmbedding (
    EmbeddingId       INT               IDENTITY PRIMARY KEY CLUSTERED,
    ChunkId           BIGINT            NOT NULL REFERENCES content.Chunk(ChunkId),
    Embedding         VECTOR(1024)      NOT NULL,  -- <- change if needed
);
GO

/* ANN index (optional; enable when your build supports it)
-- CREATE VECTOR INDEX IXV_ChunkEmbedding_Embedding
--   ON content.ChunkEmbedding (Embedding)
--   WITH (DISTANCE_METRIC = 'cosine');       -- keep consistent with queries
*/

/* Ensure the schema exists */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'care')
EXEC ('CREATE SCHEMA care AUTHORIZATION dbo;');
GO

/* ============================================================================
   Zava Healthcare (Edge) – Minimal Sign-Off Table (Doctor/PA)
   Any INSERT into this table is considered a sign-off on a patient's CarePlan.

   Columns:
     - PatientId       : NVARCHAR(64)   (reference to OPRS patient identity)
     - CarePlanJson    : NVARCHAR(MAX)  (validated JSON representing the plan)
     - DoctorNotes     : NVARCHAR(MAX)  (free text notes from doctor/PA)
     - ClinicianUser   : SYSNAME        (actual logged-in user; defaults to SUSER_SNAME())
     - ClinicianRole   : NVARCHAR(50)   ('MD','DO','PA' – extend if needed)
     - SignedUtc       : DATETIME2(3)   (UTC sign timestamp; defaults to now)

   Safe to run on a fresh database. If table exists, we leave it as-is.
============================================================================ */

SET NOCOUNT ON;

IF SCHEMA_ID('care') IS NULL
    EXEC('CREATE SCHEMA care');
GO

IF OBJECT_ID('care.PatientCarePlan','U') IS NULL
BEGIN
    CREATE TABLE care.PatientCarePlan
    (
        PatientCarePlanId  BIGINT        IDENTITY(1,1) PRIMARY KEY,

        PatientId          NVARCHAR(64)  NOT NULL,

        CarePlanJson       JSON          NOT NULL,
        DoctorNotes        NVARCHAR(MAX) NULL,

        -- Capture the actual logged-in principal
        ClinicianUser      SYSNAME       NOT NULL
            CONSTRAINT DF_PatientCarePlan_ClinicianUser DEFAULT (SUSER_SNAME()),

        ClinicianRole      NVARCHAR(50)  NOT NULL
            CONSTRAINT DF_PatientCarePlan_ClinicianRole DEFAULT ('MD'),

        SignedUtc          DATETIME2(3)  NOT NULL
            CONSTRAINT DF_PatientCarePlan_SignedUtc DEFAULT (SYSUTCDATETIME()),

        -- Guardrails
        CONSTRAINT CK_PatientCarePlan_JsonValid CHECK (ISJSON(CarePlanJson) = 1),
        CONSTRAINT CK_PatientCarePlan_Role      CHECK (ClinicianRole IN ('MD','DO','PA'))
    );

    -- Query pattern: latest sign-offs for a given patient
    CREATE INDEX IX_PatientCarePlan_Patient_SignedUtc
        ON care.PatientCarePlan (PatientId, SignedUtc DESC)
        INCLUDE (ClinicianUser, ClinicianRole);
END
ELSE
BEGIN
    PRINT 'care.PatientCarePlan already exists – no CREATE performed.';
END
GO

/* APPEND_ONLY ledger table for care-plan runs */
DROP TABLE IF EXISTS care.CarePlanLedger;
GO
CREATE TABLE care.CarePlanLedger
(
    CarePlanId        BIGINT           IDENTITY(1,1) PRIMARY KEY,
    PatientId         NVARCHAR(64)     NOT NULL,                   -- your ID format; widen if needed
    Prompt            NVARCHAR(MAX)    NOT NULL,                   -- free-text user prompt
    PatientJson       NVARCHAR(MAX)             NOT NULL,                   -- normalized patient context JSON
    PlanJson          NVARCHAR(MAX)             NULL,                       -- model-returned JSON plan (NULL on failure)
    EvidenceJson      NVARCHAR(MAX)             NULL,                       -- JSON array of top-K chunks (provenance)
    Model             NVARCHAR(200)    NOT NULL DEFAULT (N'gpt-oss'),
    OllamaUrl         NVARCHAR(4000)   NOT NULL DEFAULT (N'https://localhost/api/chat'),
    HttpStatus        INT              NULL,                       -- HTTP code from the call (e.g., 200)
    RawResponse       NVARCHAR(MAX)             NULL,                       -- full REST wrapper for audits (optional)
    CreatedUtc        DATETIME2(3)     NOT NULL DEFAULT (SYSUTCDATETIME())
)
WITH (LEDGER = ON (APPEND_ONLY = ON));  -- immutable inserts only
GO

/* Helpful read indexes */
CREATE INDEX IX_CarePlanLedger_Patient ON care.CarePlanLedger (PatientId, CreatedUtc DESC);
GO
CREATE INDEX IX_CarePlanLedger_Created ON care.CarePlanLedger (CreatedUtc DESC, PatientId);
GO

CREATE TABLE care.PatientVitals
(
    PatientId         NVARCHAR(64)     NOT NULL,
    PatientVitals     JSON             NOT NULL
);
GO


/* ========================================================================== */
/* 4) Minimal roles & grants                                                  */
/* ========================================================================== */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'role_content_reader')
    CREATE ROLE role_content_reader AUTHORIZATION dbo;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'role_care_author')
    CREATE ROLE role_care_author AUTHORIZATION dbo;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'role_care_sync')
    CREATE ROLE role_care_sync AUTHORIZATION dbo;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'role_care_signer')
    CREATE ROLE role_care_signer AUTHORIZATION dbo;
GO

GRANT SELECT ON SCHEMA::content TO role_content_reader;
GRANT EXECUTE ON SCHEMA::care TO role_care_author;


