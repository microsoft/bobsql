USE [AdventureWorks];
GO

IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'MyAzureOpenAIEmbeddingModel')
DROP EXTERNAL MODEL MyAzureOpenAIEmbeddingModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyAzureOpenAIEmbeddingModel
WITH ( 
      LOCATION = 'https://productsopenai.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15',
      API_FORMAT = 'Azure OpenAI',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'text-embedding-ada-002',
      CREDENTIAL = [https://productsopenai.openai.azure.com]
);
GO

