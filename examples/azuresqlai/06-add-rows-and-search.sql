-- ============================================================================
-- 06-add-rows-and-search.sql
-- Demonstrates adding new rows with embeddings to a table with a vector index.
-- DML is fully supported with latest-version DiskANN indexes - no rebuild needed.
-- New rows are automatically searchable after insert.
-- ============================================================================

-- Insert new rows about recent Azure SQL features
-- Embeddings are generated inline using AI_GENERATE_EMBEDDINGS
INSERT INTO dbo.azure_sql_knowledge (title, category, content, embedding)
VALUES
(N'Copilot Skills in Azure SQL Database',
 N'AI and Machine Learning',
 N'Microsoft Copilot in Azure SQL Database is a set of AI-assisted experiences designed to streamline database management. Copilot can generate T-SQL queries from natural language descriptions, explain existing queries, and help fix errors in your code. Database administrators can ask questions about performance, capabilities, and best practices. Copilot uses database context, documentation, DMVs, and Query Store data to provide relevant answers specific to your database.',
 AI_GENERATE_EMBEDDINGS(N'Microsoft Copilot in Azure SQL Database is a set of AI-assisted experiences designed to streamline database management. Copilot can generate T-SQL queries from natural language descriptions, explain existing queries, and help fix errors in your code. Database administrators can ask questions about performance, capabilities, and best practices. Copilot uses database context, documentation, DMVs, and Query Store data to provide relevant answers specific to your database.' USE MODEL EmbeddingModel));

INSERT INTO dbo.azure_sql_knowledge (title, category, content, embedding)
VALUES
(N'AI_GENERATE_EMBEDDINGS Function',
 N'AI and Machine Learning',
 N'AI_GENERATE_EMBEDDINGS is a built-in T-SQL function that creates vector embeddings using a pre-configured external model. It accepts text input and returns a vector array that captures the semantic meaning of the text. The function works with Azure OpenAI, OpenAI, Ollama, and local ONNX Runtime models configured via CREATE EXTERNAL MODEL. It can be used in SELECT, UPDATE, and INSERT statements for inline embedding generation without leaving T-SQL.',
 AI_GENERATE_EMBEDDINGS(N'AI_GENERATE_EMBEDDINGS is a built-in T-SQL function that creates vector embeddings using a pre-configured external model. It accepts text input and returns a vector array that captures the semantic meaning of the text. The function works with Azure OpenAI, OpenAI, Ollama, and local ONNX Runtime models configured via CREATE EXTERNAL MODEL. It can be used in SELECT, UPDATE, and INSERT statements for inline embedding generation without leaving T-SQL.' USE MODEL EmbeddingModel));

INSERT INTO dbo.azure_sql_knowledge (title, category, content, embedding)
VALUES
(N'SQL MCP Server for AI Agents',
 N'AI and Machine Learning',
 N'SQL MCP Server provides a stable and governed interface for AI agents to interact with Azure SQL databases. Instead of exposing raw schema or relying on generated SQL, it routes all access through a defined set of tools backed by your configuration. The Model Context Protocol (MCP) enables AI agents to discover available capabilities, understand inputs and outputs, and operate without guessing. This separates reasoning from execution so models focus on intent while SQL MCP Server handles valid query generation.',
 AI_GENERATE_EMBEDDINGS(N'SQL MCP Server provides a stable and governed interface for AI agents to interact with Azure SQL databases. Instead of exposing raw schema or relying on generated SQL, it routes all access through a defined set of tools backed by your configuration. The Model Context Protocol (MCP) enables AI agents to discover available capabilities, understand inputs and outputs, and operate without guessing. This separates reasoning from execution so models focus on intent while SQL MCP Server handles valid query generation.' USE MODEL EmbeddingModel));

INSERT INTO dbo.azure_sql_knowledge (title, category, content, embedding)
VALUES
(N'Ledger Tables for Tamper-Proof Data',
 N'Security',
 N'Azure SQL Database Ledger provides tamper-evident capabilities for your database. It uses blockchain-inspired technology to cryptographically verify that data has not been altered. Updatable ledger tables track changes with a built-in history table and generate digests that can be stored in Azure Blob Storage or Azure Confidential Ledger. Append-only ledger tables only allow inserts. Database verification checks the integrity of all ledger data using the stored digests. This is ideal for financial records, regulatory compliance, and any data requiring proof of integrity.',
 AI_GENERATE_EMBEDDINGS(N'Azure SQL Database Ledger provides tamper-evident capabilities for your database. It uses blockchain-inspired technology to cryptographically verify that data has not been altered. Updatable ledger tables track changes with a built-in history table and generate digests that can be stored in Azure Blob Storage or Azure Confidential Ledger. Append-only ledger tables only allow inserts. Database verification checks the integrity of all ledger data using the stored digests. This is ideal for financial records, regulatory compliance, and any data requiring proof of integrity.' USE MODEL EmbeddingModel));
GO

-- Verify new rows were inserted with embeddings
SELECT COUNT(*) AS total_rows FROM dbo.azure_sql_knowledge;
GO

-- Search for the newly added content - the vector index automatically includes new rows
EXEC dbo.usp_vector_search @search_text = N'How can AI agents query my database safely?';
GO

EXEC dbo.usp_vector_search @search_text = N'How do I generate embeddings in T-SQL?';
GO

EXEC dbo.usp_vector_search @search_text = N'How can I prove my data has not been tampered with?';
GO
