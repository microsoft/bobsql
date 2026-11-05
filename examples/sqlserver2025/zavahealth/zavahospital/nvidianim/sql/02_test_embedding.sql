-- =============================================
-- Script: 02_test_embedding.sql
-- Purpose: Smoke test the NIM embedding model on AKS
-- Prerequisite: 01_create_external_model.sql has been run (with actual INGRESS_IP)
-- =============================================
USE FoundryLocalTest;
GO

-- Generate an embedding for a sample phrase
SELECT AI_GENERATE_EMBEDDINGS(N'mountain bike for rugged terrain' USE MODEL NIMEmbeddingModel);
GO
