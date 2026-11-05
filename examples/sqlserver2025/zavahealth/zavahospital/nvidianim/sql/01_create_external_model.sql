-- =============================================
-- Script: 01_create_external_model.sql
-- Purpose: Create external model for NIM embeddings on AKS
-- Endpoint: https://nim-aks.local/v1/embeddings
-- Model: nvidia/nv-embedqa-e5-v5-query (1024 dimensions, -query suffix avoids input_type requirement)
-- Prerequisite: AKS cluster running with NIM deployed (deploy-nim.ps1)
-- =============================================
USE FoundryLocalTest;
GO

-- Drop external model if it already exists
IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'NIMEmbeddingModel')
    DROP EXTERNAL MODEL NIMEmbeddingModel;
GO

-- Create the EXTERNAL MODEL pointing to NIM on AKS
CREATE EXTERNAL MODEL NIMEmbeddingModel
WITH (
    LOCATION = 'https://nim-aks.local/v1/embeddings',
    API_FORMAT = 'OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'nvidia/nv-embedqa-e5-v5-query'
);
GO

-- Verify the external model was created
SELECT name, model, location, api_format FROM sys.external_models WHERE name = 'NIMEmbeddingModel';
GO
