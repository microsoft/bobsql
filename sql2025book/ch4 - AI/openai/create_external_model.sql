USE [AdventureWorksOpenAI];
GO

DROP EXTERNAL MODEL MyOpenAICompatEmbeddingModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyOpenAICompatEmbeddingModel
WITH ( 
      LOCATION = 'https://bwsqlnvidia.centralus.cloudapp.azure.com/v1/embeddings',
      API_FORMAT = 'OpenAI',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'nvidia/nv-embedqa-e5-v5-query',
      CREDENTIAL = [https://bwsqlnvidia.centralus.cloudapp.azure.com]
);
GO