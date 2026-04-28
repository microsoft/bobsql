-- ============================================================================
-- 01-setup-external-model.sql
-- Creates database master key, database scoped credential (managed identity),
-- and an external model for Azure OpenAI embeddings.
--
-- Set @AoaiName below to your Azure OpenAI resource name.
-- This script uses dynamic SQL so it runs anywhere (no SQLCMD mode required).
-- ============================================================================

-- *** SET YOUR AZURE OPENAI RESOURCE NAME HERE ***
DECLARE @AoaiName NVARCHAR(200) = N'aoai-sqlai-demo';

-- Derived values
DECLARE @CredentialName NVARCHAR(500) = N'https://' + @AoaiName + N'.openai.azure.com/';
DECLARE @ModelLocation NVARCHAR(500) = N'https://' + @AoaiName + N'.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2024-06-01';
DECLARE @sql NVARCHAR(MAX);

-- Create a database master key (required for database scoped credentials)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Str0ng!P@ssw0rd#2025';
END

-- Create database scoped credential using managed identity
-- The SQL server's system-assigned managed identity must have
-- "Cognitive Services OpenAI User" role on the Azure OpenAI resource
IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = @CredentialName)
BEGIN
    SET @sql = N'CREATE DATABASE SCOPED CREDENTIAL ' + QUOTENAME(@CredentialName)
        + N' WITH IDENTITY = ''Managed Identity'','
        + N' SECRET = ''{"resourceid":"https://cognitiveservices.azure.com"}'';';
    EXEC sp_executesql @sql;
END

-- Create external model for embeddings (text-embedding-ada-002, 1536 dimensions)
IF NOT EXISTS (SELECT * FROM sys.external_models WHERE name = 'EmbeddingModel')
BEGIN
    SET @sql = N'CREATE EXTERNAL MODEL EmbeddingModel WITH ('
        + N' LOCATION = ''' + @ModelLocation + N''','
        + N' API_FORMAT = ''Azure OpenAI'','
        + N' MODEL_TYPE = EMBEDDINGS,'
        + N' MODEL = ''text-embedding-ada-002'','
        + N' CREDENTIAL = ' + QUOTENAME(@CredentialName)
        + N');';
    EXEC sp_executesql @sql;
END

-- Verify the external model was created
SELECT * FROM sys.external_models;
SELECT * FROM sys.database_scoped_credentials WHERE name LIKE '%openai.azure.com%';
GO
