USE [AdventureWorks];
GO

-- Give it a spin
EXEC find_relevant_products_vector_search
@prompt = N'I want a gliding, pillow‑y feel on battered streets, zero buzz through the hands.',
@stock = 100,
@top = 10
GO

-- Give it a spin
EXEC find_relevant_products_vector_search
@prompt = N'Je veux une impression de douceur et de confort, même quand la route est pourrie, sans que ça vibre dans les mains',
@stock = 100,
@top = 10
GO



