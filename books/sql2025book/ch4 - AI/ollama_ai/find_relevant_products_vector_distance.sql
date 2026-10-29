USE [AdventureWorks];
GO

CREATE OR ALTER procedure [find_relevant_products]
@prompt nvarchar(max), -- NL prompt
@stock smallint = 500, -- Only show product with stock level of >= 500. User can override
@top int = 10, -- Only show top 10. User can override
@min_similarity decimal(19,16) = 0.3 -- Similarity level that user can change but recommend to leave default
as
if (@prompt is null) return;

declare @retval int, @vector vector(1024);

--exec @retval = get_embedding @prompt, @vector output;
select @vector = GET_EMBEDDINGS(MyOpenAICompatEmbeddingModel, @prompt);

if (@retval != 0) return;

-- Use vector_distance to find similar products
-- Use a hybrid search to only show products with a stock_quantity > 25

with cteSimilarEmbeddings as 
(
    select 
    top(@top)
        pde.ProductID, pde.ProductModelID, pde.ProductDescriptionID, pde.CultureID, 
        vector_distance('cosine', pde.[Embedding], @vector) as distance
    from 
        Production.ProductDescriptionEmbeddings pde
    order by
        distance 
)
select p.Name as ProductName, pd.Description as ProductDescription, p.SafetyStockLevel as StockQuantity
from 
  cteSimilarEmbeddings se
join
  Production.Product p
on p.ProductID = se.ProductID
join
  Production.ProductDescription pd
on pd.ProductDescriptionID = se.ProductDescriptionID
where   
 (1-distance) > @min_similarity
and
  p.SafetyStockLevel >= @stock
order by    
  distance asc;
GO
