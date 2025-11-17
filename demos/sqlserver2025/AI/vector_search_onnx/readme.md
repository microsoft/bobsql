# Vector Search with ONNX Runtime

This demo demonstrates how to use SQL Server 2025's vector search capabilities with ONNX Runtime for completely offline, high-performance semantic product search on the AdventureWorks database. This approach runs entirely within SQL Server with no external dependencies or network calls.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **AdventureWorks Database** - [Download AdventureWorksLT2022.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorksLT2022.bak)
- **ONNX Runtime** - [Download ONNX Runtime](https://github.com/microsoft/onnxruntime/releases)
- **ONNX Embedding Model** - Download an ONNX-format embedding model (e.g., all-MiniLM-L6-v2)
- **SQL Server Management Studio (SSMS)**

## ONNX Runtime Setup

1. **Download ONNX Runtime:**
   - Go to https://github.com/microsoft/onnxruntime/releases
   - Download the Windows release (e.g., `onnxruntime-win-x64-*.zip`)
   - Extract to `C:\onnx_runtime\` (or your preferred location)

2. **Download an ONNX Embedding Model:**
   - Many embedding models are available in ONNX format
   - Example: all-MiniLM-L6-v2 from Hugging Face
   - Convert PyTorch models to ONNX format if needed
   - Place the model files in `C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx\`

3. **Configure Paths:**
   - Note your ONNX Runtime installation path
   - Note your model directory path
   - You'll need both for the external model configuration

## Files

| File | Purpose |
|------|---------|
| `00_a_enablerestapi.sql` | Enables REST API endpoint support in SQL Server |
| `00_b_enable_preview_features.sql` | Enables PREVIEW_FEATURES configuration (alternate) |
| `00_b_restore_adventureworks.sql` | Restores the AdventureWorks sample database |
| `00_c_createft.sql` | Creates full-text catalog and index for comparison demos |
| `00_d_enable_preview_features.sql` | Enables PREVIEW_FEATURES configuration for vector indexing |
| `00_e_enable_onnx.sql` | Enables ONNX Runtime support in SQL Server |
| `01_search_productdescription.sql` | Demonstrates traditional full-text search (for comparison) |
| `02_create_external_model_onnx.sql` | Creates external model using local ONNX model |
| `03_embeddingtable.sql` | Creates table and populates it with product embeddings |
| `04_create_vector_index.sql` | Creates DiskANN vector index for fast similarity search |
| `05_find_relevant_products_vector_search.sql` | Vector search queries and examples |
| `Bonus_recall.sql` | Demonstrates recall testing and accuracy metrics |
| `Bonus_vector_distance.sql` | Shows vector distance calculations and similarity scoring |

## Step-by-Step Instructions

### Step 1: Setup SQL Server Configuration
```sql
-- Enable REST API support (may be needed for some features)
-- Run: 00_a_enablerestapi.sql
```

Enables REST API support in SQL Server (though ONNX runs locally, this may be required for other features).

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

### Step 4: Enable PREVIEW_FEATURES Configuration
```sql
-- Enable PREVIEW_FEATURES for vector indexing
-- Run: 00_d_enable_preview_features.sql
```

Enables the PREVIEW_FEATURES database scoped configuration required for vector indexing in SQL Server 2025.

### Step 5: Enable ONNX Runtime Support
```sql
-- Enable ONNX Runtime
-- Run: 00_e_enable_onnx.sql
```

**CRITICAL:** This enables SQL Server to use ONNX Runtime for local AI model execution. You may need to restart SQL Server after running this.

### Step 6: Test Traditional Search (Optional)
```sql
-- See traditional search results
-- Run: 01_search_productdescription.sql
```

Demonstrates traditional keyword and full-text search for comparison purposes.

### Step 7: Create External Model
```sql
-- Create the external model
-- Run: 02_create_external_model_onnx.sql
```

**IMPORTANT:** Edit this script to match your installation:
- Update `LOCATION` with the path to your ONNX model directory
  - Example: `C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx`
- Update `MODEL` with your model name (e.g., `allMiniLM`)
- Update `LOCAL_RUNTIME_PATH` with your ONNX Runtime installation path
  - Example: `C:\onnx_runtime\`

This creates an external model reference that SQL Server will use to generate embeddings locally using ONNX Runtime.

**Note:** Ensure the SQL Server service account has read permissions on the ONNX Runtime and model directories.

### Step 8: Generate and Store Embeddings
```sql
-- Create embeddings table and populate it
-- Run: 03_embeddingtable.sql
```

This script:
- Creates a table to store vector embeddings
- Retrieves product descriptions from AdventureWorks
- Uses ONNX Runtime to generate embeddings locally
- Stores the vector embeddings in the database

**Note:** This runs completely within SQL Server using ONNX Runtime - no network calls or external dependencies! Performance depends on your server hardware.

### Step 9: Create Vector Index
```sql
-- Create the DiskANN vector index
-- Run: 04_create_vector_index.sql
```

Creates a specialized DiskANN index optimized for fast vector similarity searches using cosine distance.

### Step 10: Run Vector Search Demos
```sql
-- Try the vector search
-- Run: 05_find_relevant_products_vector_search.sql
```

Executes example searches demonstrating:
- Natural language semantic product search
- How vector search finds relevant products based on meaning
- Completely offline operation with no external API calls

Notice how semantic search:
- Understands concepts beyond exact keywords
- Finds semantically similar products
- Works with natural language queries
- Runs entirely on your SQL Server

### Step 11: Explore Bonus Demos (Optional)

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

- How to integrate ONNX Runtime with SQL Server for local AI
- Running embedding models completely offline within SQL Server
- Creating external AI models using ONNX format
- Generating and storing vector embeddings without external APIs
- Building high-performance vector indexes
- Implementing semantic search with zero network dependencies
- Achieving maximum performance with local model execution

## Key Concepts

**ONNX (Open Neural Network Exchange):** An open format for representing machine learning models, enabling cross-platform model deployment.

**ONNX Runtime:** Microsoft's high-performance inference engine for ONNX models, optimized for production workloads.

**Embeddings:** Numerical vector representations of text that capture semantic meaning.

**Local Execution:** Models run directly in SQL Server process, no external services or network calls required.

**Vector Index (DiskANN):** Specialized index for fast approximate nearest neighbor search in high-dimensional space.

**Cosine Distance:** Similarity metric where lower distance indicates more similar vectors.

## Advantages of ONNX Runtime

✅ **Best Performance:** Runs in-process within SQL Server for minimal latency  
✅ **Completely Offline:** Zero external dependencies or network calls  
✅ **No API Costs:** No per-request charges or subscription fees  
✅ **Maximum Privacy:** All data stays within SQL Server  
✅ **Production-Ready:** ONNX Runtime is optimized for production workloads  
✅ **Hardware Acceleration:** Can leverage CPU optimizations and GPU if available  
✅ **No Rate Limits:** Process unlimited data at your hardware's speed  
✅ **Predictable Latency:** No network variability or API throttling  

## Troubleshooting

**ONNX Runtime Not Enabled:**
- Ensure you ran `00_e_enable_onnx.sql`
- Restart SQL Server after enabling
- Verify with: `SELECT * FROM sys.configurations WHERE name = 'external AI runtimes enabled'`

**Model Not Found:**
- Verify the model files exist at the specified `LOCATION` path
- Check file permissions - SQL Server service account must have read access
- Ensure the path uses the correct format (e.g., `C:\onnx_runtime\model\...`)

**ONNX Runtime Not Found:**
- Verify ONNX Runtime is extracted to the specified `LOCAL_RUNTIME_PATH`
- Check that all required DLLs are present in the directory
- Ensure the SQL Server service account has read/execute permissions

**Embedding Generation Fails:**
- Check SQL Server error logs for detailed error messages
- Verify model format is compatible with ONNX Runtime version
- Ensure model produces the expected embedding dimensions
- Test with a simple query first before bulk operations

**Performance Issues:**
- ONNX Runtime can use CPU or GPU acceleration
- Check SQL Server resource usage during embedding generation
- Consider batch processing for large datasets
- Monitor memory usage - embeddings consume significant memory

**Dimension Mismatch:**
- Verify your model's output dimensions
- Common sizes: 384 (all-MiniLM-L6-v2), 768 (base models), 1024+ (large models)
- Update table definition to match: `vector(384, float16)` or appropriate size

## Model Options

Popular ONNX embedding models:
- **all-MiniLM-L6-v2:** 384 dimensions, fast, good quality
- **all-mpnet-base-v2:** 768 dimensions, higher quality
- **text-embedding models:** Various sizes and quality levels
- **Custom models:** Convert your own PyTorch models to ONNX

## Performance Considerations

- **In-Process Execution:** Fastest option, runs within SQL Server
- **No Network Overhead:** Eliminates API call latency
- **Hardware-Dependent:** Performance scales with CPU/GPU capabilities
- **Memory Requirements:** Models and embeddings require RAM
- **Batch Processing:** Process large datasets in batches for efficiency

## Security Benefits

- **Air-Gapped Deployment:** Can run in environments without internet access
- **Data Sovereignty:** All data processing stays within your infrastructure
- **Compliance-Friendly:** Meets strict data privacy requirements
- **No Third-Party Data Sharing:** Never sends data to external services

## Next Steps

- Experiment with different ONNX models
- Compare performance with cloud-based options
- Implement hybrid search with traditional SQL queries
- Fine-tune models for your specific domain
- Measure and optimize embedding generation performance
- Build complete RAG (Retrieval Augmented Generation) solutions
- Explore GPU acceleration for even better performance
