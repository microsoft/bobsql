SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_NAME() <> N'research'
    THROW 51000, 'This schema may be deployed only to the research database.', 1;
GO

IF OBJECT_ID(N'dbo.pmc_documents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.pmc_documents
    (
        document_id INT NOT NULL,
        pmcid NVARCHAR(32) NOT NULL,
        title NVARCHAR(2000) NOT NULL,
        CONSTRAINT PK_pmc_documents PRIMARY KEY CLUSTERED (document_id),
        CONSTRAINT UQ_pmc_documents_pmcid UNIQUE (pmcid)
    );
END;
GO

IF OBJECT_ID(N'dbo.pmc_chunks', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.pmc_chunks
    (
        document_id INT NOT NULL,
        chunk_number INT NOT NULL,
        text_chunk NVARCHAR(MAX) NOT NULL,
        embedding VECTOR(512) NULL,
        CONSTRAINT PK_pmc_chunks PRIMARY KEY CLUSTERED (document_id, chunk_number),
        CONSTRAINT FK_pmc_chunks_documents FOREIGN KEY (document_id)
            REFERENCES dbo.pmc_documents (document_id),
        CONSTRAINT CK_pmc_chunks_chunk_number CHECK (chunk_number >= 0),
        CONSTRAINT CK_pmc_chunks_text CHECK (DATALENGTH(text_chunk) > 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.corpus_status', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.corpus_status
    (
        status_id TINYINT NOT NULL,
        corpus_version NVARCHAR(64) NOT NULL,
        embedding_model NVARCHAR(128) NOT NULL,
        embedding_dimensions INT NOT NULL,
        loaded_at DATETIME2(0) NOT NULL,
        embedded_at DATETIME2(0) NULL,
        CONSTRAINT PK_corpus_status PRIMARY KEY (status_id),
        CONSTRAINT CK_corpus_status_singleton CHECK (status_id = 1)
    );
END;
GO

IF DATABASE_PRINCIPAL_ID(N'CaldovaEvidenceReader') IS NULL
    CREATE ROLE CaldovaEvidenceReader AUTHORIZATION dbo;
GO
