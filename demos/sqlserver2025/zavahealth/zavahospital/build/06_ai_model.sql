/* =======================================================================
   EXTERNAL MODEL for NVIDIA NIM embeddings on AKS
   Endpoint: https://nim-aks.local/v1/embeddings
   Model: nvidia/nv-embedqa-e5-v5-query (1024 dimensions, -query suffix avoids input_type requirement)
   No credential needed — endpoint is open, TLS only
   ======================================================================= */
USE zavahospital;
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'NIMEmbeddingModel')
    DROP EXTERNAL MODEL NIMEmbeddingModel;
GO

CREATE EXTERNAL MODEL NIMEmbeddingModel
WITH (
    LOCATION   = 'https://nim-aks.local/v1/embeddings',
    API_FORMAT = 'OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'nvidia/nv-embedqa-e5-v5-query'
);
GO

-- Verify
SELECT name, model, location, api_format FROM sys.external_models WHERE name = 'NIMEmbeddingModel';
GO

