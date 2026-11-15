USE CaldovaRegionalCare;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_configurations
               WHERE name = N'PREVIEW_FEATURES' AND value = 1)
    THROW 50040, 'Run Initialize-FoundrySqlTests.ps1 -ApplicationVectorSearch first.', 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'CaldovaHistoryEmbeddingModel')
    EXEC(N'CREATE EXTERNAL MODEL CaldovaHistoryEmbeddingModel
    WITH (
        LOCATION = ''https://192.0.2.10/nemotron-3-embed-1b-bf16/v1/embeddings'',
        API_FORMAT = ''OpenAI'',
        MODEL_TYPE = EMBEDDINGS,
        MODEL = ''nemotron-3-embed-1b-bf16'',
        CREDENTIAL = [https://192.0.2.10/nemotron-3-embed-1b-bf16],
        PARAMETERS = ''{"encoding_format":"float"}''
    );');
IF NOT EXISTS (
    SELECT 1 FROM sys.external_models
    WHERE name = N'CaldovaHistoryEmbeddingModel'
      AND model = N'nemotron-3-embed-1b-bf16' AND api_format = N'OpenAI'
      AND location = N'https://192.0.2.10/nemotron-3-embed-1b-bf16/v1/embeddings'
)
    THROW 50056, 'CaldovaHistoryEmbeddingModel has an unexpected definition; no replacement was made.', 1;
GO
