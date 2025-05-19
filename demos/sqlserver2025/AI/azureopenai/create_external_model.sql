USE [AdventureWorks];
GO

DROP EXTERNAL MODEL MyAzureOpenAIEmbeddingModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyAzureOpenAIEmbeddingModel
WITH ( 
      LOCATION = 'https://<azureai>/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15',
      API_FORMAT = 'Azure OpenAI',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'text-embedding-ada-002',
      CREDENTIAL = [https://<azureai>]
);
GO

