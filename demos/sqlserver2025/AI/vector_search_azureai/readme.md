# Vector Search with Azure OpenAI

This demo demonstrates how to use SQL Server 2025's vector search capabilities with Azure OpenAI's embedding models to perform semantic product search on the AdventureWorks database.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **AdventureWorks Database** - [Download AdventureWorksLT2022.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorksLT2022.bak)
- **Azure OpenAI Service** - You'll need an Azure subscription with Azure OpenAI access and a deployed embedding model
- **SQL Server Management Studio (SSMS)**

## Azure OpenAI Setup

Before running the demos, you need:
1. An Azure OpenAI resource in your Azure subscription
2. A deployed embedding model (e.g., `text-embedding-3-large`)
3. The endpoint URL and API key for your deployment

## Files

| File | Purpose |
|------|---------|
| `00_a_enablerestapi.sql` | Enables REST API endpoint support in SQL Server |
| `00_b_restore_adventureworks.sql` | Restores the AdventureWorks sample database |
| `00_c_createft.sql` | Creates full-text catalog and index for comparison demos |
| `00_d_enable_preview_features.sql` | Enables SQL Server 2025 preview features |
| `00_e_creds.sql` | Creates database master key and Azure OpenAI credentials |
| `00_f_search_productdescription.sql` | Demonstrates traditional full-text search (for comparison) |
| `01_create_external_model_azureai.sql` | Creates external model pointing to Azure OpenAI |
| `02_embeddingtable.sql` | Creates table and populates it with product embeddings |
| `03_create_vector_index.sql` | Creates DiskANN vector index for fast similarity search |
| `04_find_relevant_products_proc.sql` | Creates stored procedure for semantic product search |
| `05_vector_search.sql` | Demo queries showing vector search in action |
| `Bonus_recall.sql` | Demonstrates recall testing and accuracy metrics |
| `Bonus_vector_distance.sql` | Shows vector distance calculations and similarity scoring |

## Step-by-Step Instructions

### Step 1: Setup SQL Server Configuration
Run the following scripts in order to configure SQL Server:

```sql
-- Enable REST API support
-- Run: 00_a_enablerestapi.sql
```

This enables SQL Server to make REST API calls to Azure OpenAI.

### Step 2: Restore AdventureWorks Database
```sql
-- Restore the database
-- Run: 00_b_restore_adventureworks.sql
```

Restores the AdventureWorks sample database that contains product information.

### Step 3: Setup Full-Text Search (Optional)
```sql
-- Create full-text catalog and index
-- Run: 00_c_createft.sql
```

This is optional but useful for comparing traditional search with vector search.

### Step 4: Enable Preview Features
```sql
-- Enable SQL Server 2025 preview features
-- Run: 00_d_enable_preview_features.sql
```

Enables the AI and vector search features in SQL Server 2025.

### Step 5: Configure Azure OpenAI Credentials
```sql
-- Setup credentials
-- Run: 00_e_creds.sql
```

**IMPORTANT:** Before running this script, edit it to include your Azure OpenAI API key and endpoint URL. Update these values:
- Replace the endpoint URL in the `CREATE DATABASE SCOPED CREDENTIAL` statement
- Replace the API key in the `SECRET` parameter

### Step 6: Test Traditional Search (Optional)
```sql
-- See traditional search results
-- Run: 00_f_search_productdescription.sql
```

This demonstrates traditional keyword and full-text search to compare with semantic search later.

### Step 7: Create External Model
```sql
-- Create the external model
-- Run: 01_create_external_model_azureai.sql
```

**IMPORTANT:** Edit this script to match your Azure OpenAI deployment:
- Update the `LOCATION` with your Azure OpenAI endpoint URL
- Update the `MODEL` parameter with your deployment name
- Update the `CREDENTIAL` name to match your endpoint

This creates an external model reference that SQL Server will use to generate embeddings.

### Step 8: Generate and Store Embeddings
```sql
-- Create embeddings table and populate it
-- Run: 02_embeddingtable.sql
```

This creates a table to store vector embeddings and populates it by:
- Getting product descriptions from AdventureWorks
- Calling Azure OpenAI to generate embeddings for each description
- Storing the 3072-dimensional vectors in the database

**Note:** This may take a few minutes depending on the number of products and API rate limits.

### Step 9: Create Vector Index
```sql
-- Create the DiskANN vector index
-- Run: 03_create_vector_index.sql
```

Creates a specialized DiskANN index optimized for fast vector similarity searches using cosine distance metric.

### Step 10: Create Search Stored Procedure
```sql
-- Create the search procedure
-- Run: 04_find_relevant_products_proc.sql
```

Creates a stored procedure that:
- Accepts a natural language prompt
- Generates an embedding for the prompt
- Searches for similar product embeddings
- Returns relevant products with their descriptions

### Step 11: Run Vector Search Demos
```sql
-- Try the vector search
-- Run: 05_vector_search.sql
```

Executes example searches including:
- English language product search
- French language product search (demonstrates multilingual capabilities)

Notice how semantic search finds relevant products even when:
- The exact words aren't in the description
- Different languages are used
- Concepts are described rather than specific keywords

### Step 12: Explore Bonus Demos (Optional)

**Recall Testing:**
```sql
-- Run: Bonus_recall.sql
```
Demonstrates how to measure the accuracy and recall of your vector search.

**Vector Distance:**
```sql
-- Run: Bonus_vector_distance.sql
```
Shows how to calculate and interpret vector distances and similarity scores.

## What You'll Learn

- How to integrate Azure OpenAI embeddings with SQL Server
- Creating and managing external AI models in SQL Server
- Generating and storing vector embeddings
- Building high-performance vector indexes
- Implementing semantic search that understands meaning, not just keywords
- Multilingual search capabilities
- Comparing traditional vs. semantic search approaches

## Key Concepts

**Embeddings:** Numerical representations of text that capture semantic meaning. Similar concepts have similar vector representations.

**Vector Index:** Specialized index (DiskANN) that enables fast approximate nearest neighbor search in high-dimensional vector space.

**Cosine Distance:** Metric used to measure similarity between vectors. Lower distance = more similar.

**Semantic Search:** Search based on meaning and context rather than exact keyword matching.

## Troubleshooting

**REST API Error:** Make sure you've enabled the REST API endpoint (Step 1) and restarted SQL Server.

**Authentication Failed:** Verify your Azure OpenAI API key and endpoint URL are correct in the credentials script.

**Model Not Found:** Ensure your Azure OpenAI deployment name matches what's in the external model script.

**Slow Embedding Generation:** This is normal for large datasets. Consider processing in batches or using a higher-tier Azure OpenAI deployment.

## Next Steps

- Modify the search stored procedure to add filtering by price, category, etc.
- Experiment with different similarity thresholds
- Try different embedding models
- Implement hybrid search combining vector and full-text search
- Compare performance with and without the vector index
