USE [AdventureWorks];
GO

IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'MyAzureOpenAIModel')
DROP EXTERNAL MODEL MyAzureOpenAIModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyAzureOpenAIModel
WITH ( 
      LOCATION = 'https://productsopenai.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings?api-version=2023-05-15',
      API_FORMAT = 'Azure OpenAI',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'text-embedding-3-large',
      CREDENTIAL = [https://productsopenai.openai.azure.com],
      PARAMETERS = '{ "sql_rest_options": { "retry_count": 10 } }'
      );
GO


SELECT * FROM sys.external_models;
GO

SELECT AI_GENERATE_EMBEDDINGS(N'Hello from SQL' USE MODEL MyAzureOpenAIModel);
GO