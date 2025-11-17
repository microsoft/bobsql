# Vector Search with OpenAI-Compatible APIs

This demo demonstrates how to use SQL Server 2025's vector search capabilities with OpenAI-compatible API endpoints for semantic product search on the AdventureWorks database.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **AdventureWorks Database** - [Download AdventureWorksLT2022.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorksLT2022.bak)
- **OpenAI-Compatible Service** - Either:
  - OpenAI API account with API key
  - Local service running OpenAI-compatible API (e.g., Ollama with OpenAI compatibility)
- **SQL Server Management Studio (SSMS)**

## OpenAI API Setup

You'll need an OpenAI-compatible endpoint that supports embeddings. This could be:
- **OpenAI API:** Requires an API key from OpenAI
- **Local OpenAI-Compatible Service:** Such as Ollama running with OpenAI compatibility mode
- **Other Compatible Services:** Any service implementing the OpenAI embeddings API format

## Files

| File | Purpose |
|------|---------|
| `00_a_enablerestapi.sql` | Enables REST API endpoint support in SQL Server |
| `00_b_restore_adventureworks.sql` | Restores the AdventureWorks sample database |
| `00_c_createft.sql` | Creates full-text catalog and index for comparison demos |
| `00_d_enable_preview_features.sql` | Enables SQL Server 2025 preview features |
| `00_e_search_productdescription.sql` | Demonstrates traditional full-text search (for comparison) |
| `01_search_productdescription.sql` | Traditional search examples for comparison |
| `02_create_external_model_openai.sql` | Creates external model using OpenAI API format |
| `03_embeddingtable.sql` | Creates table and populates it with product embeddings |
| `04_create_vector_index.sql` | Creates DiskANN vector index for fast similarity search |
| `05_find_relevant_products_vector_search.sql` | Vector search queries and examples |
| `Bonus_recall.sql` | Demonstrates recall testing and accuracy metrics |
| `Bonus_vector_distance.sql` | Shows vector distance calculations and similarity scoring |

## Step-by-Step Instructions

### Step 1: Setup SQL Server Configuration
```sql
-- Enable REST API support
-- Run: 00_a_enablerestapi.sql
```

This enables SQL Server to make REST API calls to OpenAI-compatible services.

### Step 2: Restore AdventureWorks Database
```sql
-- Restore the database
-- Run: 00_b_restore_adventureworks.sql
```

Restores the AdventureWorks sample database containing product information.

### Step 3: Setup Full-Text Search (Optional)
```sql
-- Create full-text catalog and index
-- Run: 00_c_createft.sql
```

Optional but useful for comparing traditional search with vector search.

### Step 4: Enable Preview Features
```sql
-- Enable SQL Server 2025 preview features
-- Run: 00_d_enable_preview_features.sql
```

Enables the AI and vector search features in SQL Server 2025.

### Step 5: Test Traditional Search (Optional)
```sql
-- See traditional search results
-- Run: 00_e_search_productdescription.sql
-- Or run: 01_search_productdescription.sql
```

Demonstrates traditional keyword and full-text search for comparison purposes.

### Step 6: Create External Model
```sql
-- Create the external model
-- Run: 02_create_external_model_openai.sql
```

**IMPORTANT:** Before running, edit this script to configure your OpenAI-compatible endpoint:
- Update the `LOCATION` with your API endpoint URL
  - For OpenAI: `https://api.openai.com/v1/embeddings`
  - For local Ollama with OpenAI compatibility: `https://localhost:11434/v1/embeddings`
  - For other services: Your service's embeddings endpoint
- Update the `MODEL` parameter with your model name (e.g., `text-embedding-3-small`)
- If using OpenAI or a service requiring authentication, add credentials:
  ```sql
  CREATE DATABASE SCOPED CREDENTIAL [your-endpoint]
  WITH IDENTITY = 'HTTPEndpointHeaders', 
  SECRET = '{"Authorization": "Bearer YOUR_API_KEY"}';
  ```

This creates an external model reference for generating embeddings.

### Step 7: Generate and Store Embeddings
```sql
-- Create embeddings table and populate it
-- Run: 03_embeddingtable.sql
```

This script:
- Creates a table to store vector embeddings
- Retrieves product descriptions from AdventureWorks
- Calls your OpenAI-compatible API to generate embeddings
- Stores the vector embeddings in the database

**Note:** Processing time depends on the number of products and API rate limits. If using a paid API, monitor your usage.

### Step 8: Create Vector Index
```sql
-- Create the DiskANN vector index
-- Run: 04_create_vector_index.sql
```

Creates a specialized DiskANN index optimized for fast vector similarity searches using cosine distance.

### Step 9: Run Vector Search Demos
```sql
-- Try the vector search
-- Run: 05_find_relevant_products_vector_search.sql
```

Executes example searches showing:
- Semantic product search using natural language
- How vector search finds relevant products based on meaning
- Comparison with traditional keyword search

Notice how semantic search:
- Understands concepts beyond exact keywords
- Finds semantically similar products
- Works with natural language queries

### Step 10: Explore Bonus Demos (Optional)

**Recall Testing:**
```sql
-- Run: Bonus_recall.sql
```
Learn how to measure search accuracy and recall of your vector search implementation.

**Vector Distance:**
```sql
-- Run: Bonus_vector_distance.sql
```
Explore vector distance calculations and similarity score interpretation.

## What You'll Learn

- How to integrate OpenAI-compatible APIs with SQL Server
- Creating external AI models using OpenAI API format
- Generating and storing vector embeddings in SQL Server
- Building high-performance vector indexes
- Implementing semantic search based on meaning
- Comparing traditional keyword search vs. semantic vector search

## Key Concepts

**OpenAI API Format:** A standardized API format for AI models that many services implement, making them interchangeable.

**Embeddings:** Numerical vector representations of text that capture semantic meaning.

**Vector Index (DiskANN):** Specialized index for fast approximate nearest neighbor search in high-dimensional space.

**Cosine Distance:** Similarity metric where lower distance indicates more similar vectors.

**Semantic Search:** Search based on understanding meaning and context, not just matching keywords.

## Troubleshooting

**REST API Error:** Ensure you've enabled the REST API endpoint (Step 1) and restarted SQL Server if needed.

**Connection Failed:** Verify your endpoint URL is correct and accessible from the SQL Server machine.

**Authentication Error:** Check that your API key is correct and properly formatted in the credential.

**Model Not Found:** Ensure the model name in your external model definition matches what's available at your endpoint.

**Rate Limiting:** If using a paid API, you may hit rate limits. Consider adding delays between requests or processing in smaller batches.

**Dimension Mismatch:** Make sure the embedding dimension in your table definition matches what your model produces.

## Flexibility of OpenAI API Format

The OpenAI API format is widely supported, giving you flexibility to:
- Start with OpenAI's hosted service
- Switch to local models for development
- Use alternative providers without changing SQL code
- Run completely offline with local compatible services

## Next Steps

- Experiment with different embedding models
- Try different OpenAI-compatible services
- Implement filtering by product attributes
- Adjust similarity thresholds for your use case
- Combine vector search with traditional SQL filtering
- Build hybrid search solutions
