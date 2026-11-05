USE [AdventureWorks];
GO

IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'MyOllamaEmbeddingModel')
DROP EXTERNAL MODEL MyOllamaEmbeddingModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyOllamaEmbeddingModel
WITH ( 
      LOCATION = 'https://localhost/api/embed',
      API_FORMAT = 'Ollama',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'mxbai-embed-large',
      PARAMETERS = '{ "sql_rest_options": { "retry_count": 10 } }'
      );
GO


SELECT * FROM sys.external_models;
GO

SELECT AI_GENERATE_EMBEDDINGS(N'Hello from SQL' USE MODEL MyOllamaEmbeddingModel);
GO