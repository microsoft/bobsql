-- =============================================
-- Script: 04_test_chat_completion.sql
-- Purpose: Test chat completion via sp_invoke_external_rest_endpoint
--          calling NIM llama-3.2-3b-instruct on AKS
-- Endpoint: https://nim-aks.local/v1/chat/completions
-- Model: meta/llama-3.2-3b-instruct
-- Prerequisite: 03_enable_rest_endpoint.sql has been run, NIM pods running on AKS
-- =============================================
USE FoundryLocalTest;
GO

DECLARE @url NVARCHAR(4000) = N'https://nim-aks.local/v1/chat/completions';

DECLARE @payload NVARCHAR(MAX) = N'{
    "model": "meta/llama-3.2-3b-instruct",
    "messages": [
        {"role": "system", "content": "You are a helpful SQL Server expert. Be concise. Use only facts from Microsoft documentation at https://learn.microsoft.com/sql/. SQL Server 2025 introduces native vector data type support with the vector(n) type, vector_distance() function for similarity search (cosine, dot product, Euclidean), and DiskANN-based vector indexing for approximate nearest neighbor (ANN) search. The CREATE VECTOR INDEX statement creates a DiskANN index on a vector column for fast ANN queries."},
        {"role": "user", "content": "What is a vector index in SQL Server 2025?"}
    ],
    "max_tokens": 256,
    "temperature": 0.7
}';

DECLARE @ret INT;
DECLARE @response NVARCHAR(MAX);

EXEC @ret = sp_invoke_external_rest_endpoint
    @url = @url,
    @payload = @payload,
    @method = 'POST',
    @timeout = 120,
    @response = @response OUTPUT;

-- Show return code and extract the assistant's reply
SELECT @ret AS ReturnCode;
SELECT JSON_VALUE(@response, '$.result.choices[0].message.content') AS ChatResponse;
SELECT @response AS FullResponse;
GO
