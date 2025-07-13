USE AdventureWorks;
GO

DROP EXTERNAL MODEL MyAzureOpenAIEmbeddingModel;
GO

DROP DATABASE SCOPED CREDENTIAL [https://<azureai>.openai.azure.com];
GO

-- Create access credentials to Azure OpenAI using a managed identity:
CREATE DATABASE SCOPED CREDENTIAL [https://<azureai>.openai.azure.com]
    WITH IDENTITY = 'Managed Identity', secret = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyAzureOpenAIEmbeddingModel
WITH ( 
      LOCATION = 'https://<azureai>.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15',
      API_FORMAT = 'Azure OpenAI',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'text-embedding-ada-002',
      CREDENTIAL = [https://<azureai>.openai.azure.com]
);
GO