USE [AdventureWorks];
GO

IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'MyLocalONNXModel')
DROP EXTERNAL MODEL MyLocalONNXModel;
GO

-- Create the EXTERNAL MODEL
CREATE EXTERNAL MODEL MyLocalONNXModel
WITH ( 
        LOCATION = 'C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx',
        API_FORMAT = 'ONNX Runtime',
        MODEL_TYPE = EMBEDDINGS,
        MODEL = 'allMiniLM',
        PARAMETERS = '{"valid":"JSON"}',
        LOCAL_RUNTIME_PATH = 'C:\onnx_runtime\'
      );
GO

SELECT * FROM sys.external_models;
GO

SELECT AI_GENERATE_EMBEDDINGS(N'Hello from SQL' USE MODEL MyLocalONNXModel);
GO