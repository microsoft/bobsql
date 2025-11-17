# Vector Search with Ollama

This demo demonstrates how to use SQL Server 2025's vector search capabilities with Ollama's local embedding models for semantic product search on the AdventureWorks database. This approach runs completely on-premises with no external API dependencies.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **AdventureWorks Database** - [Download AdventureWorksLT2022.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorksLT2022.bak)
- **Ollama** - [Download and install Ollama](https://ollama.ai)
- **Embedding Model** - Pull the embedding model: `ollama pull mxbai-embed-large`
- **SQL Server Management Studio (SSMS)**

## Ollama Setup

1. Install Ollama from https://ollama.ai
2. Pull the embedding model:
   ```bash
   ollama pull mxbai-embed-large
   ```
3. Verify Ollama is running (default: http://localhost:11434)
4. Test the model:
   ```bash
   ollama run mxbai-embed-large
   ```

## Files

| File | Purpose |
|------|---------|
| `00_a_enablerestapi.sql` | Enables REST API endpoint support in SQL Server |
| `00_b_restore_adventureworks.sql` | Restores the AdventureWorks sample database |
| `00_c_createft.sql` | Creates full-text catalog and index for comparison demos |
| `00_d_enable_preview_features.sql` | Enables SQL Server 2025 preview features |
| `00_e_search_productdescription.sql` | Demonstrates traditional full-text search (for comparison) |
| `01_create_external_model.sql` | Creates external model pointing to local Ollama |
| `02_embeddingtable.sql` | Creates table and populates it with product embeddings |
| `03_create_vector_index.sql` | Creates DiskANN vector index for fast similarity search |
| `04_find_relevant_products_proc.sql` | Creates stored procedure for semantic product search |
| `05_vector_search.sql` | Demo queries showing vector search in action |
| `Bonus_recall.sql` | Demonstrates recall testing and accuracy metrics |
| `Bonus_vector_distance.sql` | Shows vector distance calculations and similarity scoring |

## Step-by-Step Instructions

### Step 1: Setup SQL Server Configuration
```sql
-- Enable REST API support
-- Run: 00_a_enablerestapi.sql
```

This enables SQL Server to make REST API calls to your local Ollama instance.

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
```

Demonstrates traditional keyword and full-text search for comparison purposes.

### Step 6: Verify Ollama is Running

Before proceeding, ensure Ollama is running and accessible:
- Default URL: `http://localhost:11434`
- Test by visiting `http://localhost:11434` in a browser (you should see "Ollama is running")
- Verify the model is available: `ollama list` should show `mxbai-embed-large`

### Step 7: Create External Model
```sql
-- Create the external model
-- Run: 01_create_external_model.sql
```

**IMPORTANT:** Edit this script if needed to match your Ollama configuration:
- Default `LOCATION` is `https://localhost/api/embed` (Ollama's embed endpoint)
- If Ollama runs on a different port, update the URL (e.g., `http://localhost:11434/api/embed`)
- The `MODEL` should match your pulled model: `mxbai-embed-large`
- No credentials needed for local Ollama

This creates an external model reference that SQL Server will use to generate embeddings locally.

### Step 8: Generate and Store Embeddings
```sql
-- Create embeddings table and populate it
-- Run: 02_embeddingtable.sql
```

This script:
- Creates a table to store vector embeddings
- Retrieves product descriptions from AdventureWorks
- Calls your local Ollama instance to generate embeddings
- Stores the vector embeddings in the database

**Note:** This processes locally on your machine, so performance depends on your hardware. No external API calls or costs!

### Step 9: Create Vector Index
```sql
-- Create the DiskANN vector index
-- Run: 03_create_vector_index.sql
```

Creates a specialized DiskANN index optimized for fast vector similarity searches using cosine distance.

### Step 10: Create Search Stored Procedure
```sql
-- Create the search procedure
-- Run: 04_find_relevant_products_proc.sql
```

Creates a stored procedure that:
- Accepts a natural language prompt
- Generates an embedding using your local Ollama model
- Searches for similar product embeddings
- Returns relevant products with their descriptions

### Step 11: Run Vector Search Demos
```sql
-- Try the vector search
-- Run: 05_vector_search.sql
```

Executes example searches including:
- Natural language product search queries
- Demonstrates semantic understanding vs. keyword matching

Notice how semantic search:
- Finds relevant products even without exact keyword matches
- Understands the intent behind natural language queries
- Works completely offline with no external API dependencies

### Step 12: Explore Bonus Demos (Optional)

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

- How to integrate local Ollama models with SQL Server
- Running AI embeddings completely on-premises
- Creating and managing external AI models in SQL Server
- Generating and storing vector embeddings locally
- Building high-performance vector indexes
- Implementing semantic search without external API dependencies
- Privacy-preserving AI integration (all data stays local)

## Key Concepts

**Ollama:** Local AI model runtime that lets you run large language models and embedding models on your own hardware.

**mxbai-embed-large:** A high-quality embedding model that runs locally, producing 1024-dimensional vectors.

**Embeddings:** Numerical representations of text that capture semantic meaning. Similar concepts have similar vectors.

**Vector Index (DiskANN):** Specialized index for fast approximate nearest neighbor search in high-dimensional space.

**Cosine Distance:** Similarity metric where lower distance indicates more similar vectors.

**Semantic Search:** Search based on understanding meaning and context, not just matching keywords.

## Advantages of Ollama

✅ **Privacy:** All data processing happens locally - nothing sent to external services  
✅ **No API Costs:** Completely free to run once installed  
✅ **Offline Operation:** Works without internet connectivity  
✅ **Customizable:** Use different models or fine-tune for your needs  
✅ **Development-Friendly:** Easy to set up and experiment with  
✅ **No Rate Limits:** Process as much data as your hardware can handle  

## Troubleshooting

**REST API Error:** Ensure you've enabled the REST API endpoint (Step 1) and restarted SQL Server if needed.

**Cannot Connect to Ollama:** 
- Verify Ollama is running: `ollama list`
- Check the Ollama URL in your external model definition
- Ensure firewall allows localhost connections
- Try accessing http://localhost:11434 in a browser

**Model Not Found:**
- Verify the model is pulled: `ollama list`
- Pull the model if missing: `ollama pull mxbai-embed-large`
- Check the model name in your external model definition matches exactly

**Slow Performance:**
- Embedding generation is CPU/GPU intensive
- Consider processing in smaller batches
- Performance depends on your hardware capabilities
- Monitor CPU/GPU usage while processing

**Dimension Mismatch:**
- The `mxbai-embed-large` model produces 1024-dimensional vectors
- Ensure your table definition matches: `vector(1024, float16)`

## Hardware Considerations

Ollama runs on your local machine:
- **CPU:** Works on CPU but GPU is much faster
- **RAM:** Recommend at least 8GB, more for larger models
- **GPU:** NVIDIA GPU with CUDA support provides best performance
- **Disk:** Models require several GB of storage

## Next Steps

- Try different Ollama embedding models
- Experiment with other Ollama models for text generation
- Implement hybrid search combining vector and traditional SQL
- Fine-tune embedding models for your specific domain
- Measure performance differences between models
- Build a complete RAG (Retrieval Augmented Generation) solution
