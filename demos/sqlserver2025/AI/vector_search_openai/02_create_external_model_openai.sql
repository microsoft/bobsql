USE [AdventureWorks];
GO

IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'MyOpenAIModel')
DROP EXTERNAL MODEL MyOpenAIModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyOpenAIModel
WITH ( 
      LOCATION = 'https://localhost/v1/embeddings', -- This is the syntax to use the OpenAI API compatible endpoint for Ollama.
      API_FORMAT = 'OpenAI',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'embeddinggemma',
      PARAMETERS = '{ "sql_rest_options": { "retry_count": 10 } }'
      );
GO

SELECT * FROM sys.external_models;
GO

SELECT AI_GENERATE_EMBEDDINGS(N'Hello from SQL' USE MODEL MyOpenAIModel);
GO