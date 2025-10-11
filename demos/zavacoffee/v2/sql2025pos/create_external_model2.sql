USE [zavapos];
GO

IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'MyLocalEmbeddingModel')
DROP EXTERNAL MODEL MyLocalEmbeddingModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyLocalEmbeddingModel
WITH ( 
      LOCATION = 'https://localhost/api/embed',
      API_FORMAT = 'Ollama',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'mxbai-embed-large');
GO

SELECT * FROM sys.external_models;
GO