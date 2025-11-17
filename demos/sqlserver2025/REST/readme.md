# REST API Integration with Vector Search

This demo demonstrates a complete healthcare RAG (Retrieval Augmented Generation) solution using SQL Server 2025's REST API capabilities combined with vector search and AI embeddings.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **SQL Server Management Studio (SSMS)**
- **Ollama** - [Download and install Ollama](https://ollama.ai) with `mxbai-embed-large` model
- Run: `ollama pull mxbai-embed-large`

## Overview

This demo showcases a complete healthcare application scenario where SQL Server 2025 integrates with external AI services via REST APIs to provide intelligent patient care recommendations. The solution combines:

- REST API integration with Ollama for embeddings
- Vector search for semantic similarity
- Healthcare knowledge base with patient data
- RAG pattern for care plan generation
- Secure handling of PHI (Protected Health Information)

## Files

| File | Purpose |
|------|---------|
| `00_prereqs.sql` | Enables REST API endpoint support |
| `01_schema.sql` | Creates database schema with knowledge base and patient tables |
| `03_seeddata.sql` | Loads sample healthcare documents and patient data |
| `04_generate_embeddings.sql` | Generates vector embeddings for knowledge base |
| `05_create_vector_index.sql` | Creates DiskANN vector index for fast search |
| `06_create_proc_for_vector_search.sql` | Creates stored procedure for semantic search |
| `07_example_vector_search.sql` | Demonstrates vector search queries |
| `08_care_plan_prompt.sql` | Generates personalized care plan prompts |

## Architecture

```
Healthcare Knowledge Base (Non-PHI)
    ↓
Documents → Chunks → Embeddings (via Ollama REST API)
    ↓
Vector Index (Fast Semantic Search)
    ↓
Patient Data (PHI - Separate Schema)
    ↓
RAG: Retrieve Relevant Knowledge + Patient Context
    ↓
Generate Personalized Care Plan Prompts
```

## Step-by-Step Instructions

### Step 1: Enable REST API Support
```sql
-- Run: 00_prereqs.sql
```

Enables SQL Server to make REST API calls to external services like Ollama.

**Important:** After running this, you may need to restart SQL Server.

### Step 2: Create Database Schema
```sql
-- Run: 01_schema.sql
```

This comprehensive script creates:

**Knowledge Base Schema (content):**
- `Document` - Healthcare documents (guidelines, protocols)
- `Chunk` - Document chunks for embedding
- `ChunkEmbedding` - Vector embeddings of chunks

**Patient Data Schema (patient):**
- `Patient` - Patient demographics (PHI)
- `Condition` - Patient conditions
- `Medication` - Current medications
- `Observation` - Vital signs and measurements
- `CarePlan` - Generated care plans

**External Model:**
- Creates external model pointing to local Ollama instance
- Configures `mxbai-embed-large` embedding model
- Enables vector search features

**Key Design:** Separates PHI (patient schema) from non-PHI (content schema) for security and compliance.

### Step 3: Load Sample Data
```sql
-- Run: 03_seeddata.sql
```

Seeds the database with:
- Healthcare documents (diabetes management, hypertension, medication protocols)
- Document chunks for vector search
- Sample patient records with conditions and medications
- Observations and vital signs

This provides a realistic healthcare scenario for testing.

### Step 4: Generate Embeddings
```sql
-- Run: 04_generate_embeddings.sql
```

For each document chunk:
1. Calls Ollama via REST API
2. Generates vector embeddings using `mxbai-embed-large`
3. Stores embeddings in `ChunkEmbedding` table

**Note:** This may take a few minutes depending on the number of chunks and your hardware.

### Step 5: Create Vector Index
```sql
-- Run: 05_create_vector_index.sql
```

Creates a DiskANN vector index on embeddings for fast semantic similarity search using cosine distance metric.

### Step 6: Create Search Stored Procedure
```sql
-- Run: 06_create_proc_for_vector_search.sql
```

Creates `FindRelevantKnowledge` stored procedure that:
- Accepts a text query
- Generates embedding for the query
- Performs vector similarity search
- Returns relevant knowledge base chunks
- Includes similarity scores

### Step 7: Test Vector Search
```sql
-- Run: 07_example_vector_search.sql
```

Demonstrates semantic search queries:
- Search for diabetes management guidance
- Find hypertension protocols
- Retrieve medication information
- Show how similar concepts are found even with different wording

### Step 8: Generate Care Plan Prompts
```sql
-- Run: 08_care_plan_prompt.sql
```

The final demonstration shows the complete RAG pattern:

1. **Retrieve Patient Context** - Get patient conditions, medications, observations
2. **Semantic Search** - Find relevant knowledge base content
3. **Generate Prompt** - Combine patient data + relevant knowledge
4. **Output** - Structured prompt ready for LLM to generate care plan

Example output:
```
You are a healthcare AI assistant. Generate a care plan based on:

Patient: John Doe, Age 58
Conditions: Type 2 Diabetes, Hypertension
Current Medications: Metformin 1000mg, Lisinopril 10mg
Recent Vitals: BP 145/92, Blood Glucose 156

Relevant Clinical Knowledge:
[Retrieved from vector search...]

Generate appropriate care recommendations.
```

## What You'll Learn

- Integrating SQL Server with external REST APIs
- Building RAG (Retrieval Augmented Generation) patterns
- Implementing vector search for healthcare knowledge
- Separating PHI from non-PHI data
- Creating external AI models in SQL Server
- Generating embeddings via REST APIs
- Building semantic search systems
- Combining structured data with unstructured knowledge
- Generating contextual prompts for LLMs

## Key Concepts

**RAG (Retrieval Augmented Generation):** A pattern that retrieves relevant information from a knowledge base before generating responses, improving accuracy and grounding.

**Vector Embeddings:** Numerical representations that capture semantic meaning, enabling similarity search.

**PHI (Protected Health Information):** Patient identifiable health data requiring special security and compliance measures.

**External Model:** SQL Server 2025 feature to integrate external AI models via REST APIs.

**Semantic Search:** Search based on meaning rather than keyword matching.

**DiskANN Index:** High-performance vector index for approximate nearest neighbor search.

## Healthcare Use Cases

- **Clinical Decision Support** - Retrieve relevant protocols and guidelines
- **Care Plan Generation** - Create personalized patient care plans
- **Medical Literature Search** - Find relevant research and documentation
- **Medication Guidance** - Match patient conditions with treatment protocols
- **Patient Education** - Generate tailored patient information
- **Quality Assurance** - Ensure adherence to clinical guidelines

## Architecture Benefits

✅ **Separation of Concerns** - PHI separate from knowledge base  
✅ **Scalable** - Vector search scales to large knowledge bases  
✅ **Semantic Understanding** - Finds relevant content by meaning  
✅ **Real-time** - Fast vector search with DiskANN indexing  
✅ **Flexible** - Easy to update knowledge base without changing code  
✅ **Integrated** - Everything in SQL Server (data + AI)  
✅ **Secure** - PHI stays in database, knowledge base can be non-PHI  

## Security Considerations

**PHI Protection:**
- Store PHI in separate schema with restricted access
- Use SQL Server security features (Row-Level Security, Dynamic Data Masking)
- Audit access to patient data
- Encrypt sensitive data at rest and in transit

**Knowledge Base:**
- Can contain general medical knowledge (non-PHI)
- Separate physical storage if needed
- Version control for clinical guidelines

**API Integration:**
- Local Ollama keeps data on-premises
- No external API calls with patient data
- Consider Azure OpenAI with private endpoints for production

## Performance Optimization

- **Vector Index** - DiskANN provides fast approximate nearest neighbor search
- **Batch Processing** - Generate embeddings in batches for large datasets
- **Computed Columns** - Pre-compute frequently accessed patient summaries
- **Materialized Views** - Cache common patient data aggregations
- **Connection Pooling** - Reuse connections for REST API calls

## Troubleshooting

**REST API Not Enabled:** Ensure you've run `00_prereqs.sql` and restarted SQL Server.

**Ollama Connection Failed:** 
- Verify Ollama is running (`ollama list`)
- Check the endpoint URL in external model definition
- Ensure firewall allows localhost connections

**Embedding Generation Slow:** Normal for CPU-only processing. Consider GPU acceleration with Ollama.

**Vector Search Returns No Results:** 
- Check that embeddings were generated successfully
- Verify vector index was created
- Adjust similarity thresholds

## Production Considerations

1. **Scale Ollama** - Use GPU for faster embedding generation
2. **Consider Azure OpenAI** - For managed, enterprise-grade AI
3. **Implement Caching** - Cache embeddings and search results
4. **Monitor Performance** - Track API latency and search times
5. **HIPAA Compliance** - Ensure all components meet healthcare requirements
6. **Backup Strategy** - Regular backups of knowledge base and patient data
7. **Version Control** - Track changes to clinical guidelines
8. **Audit Logging** - Log all access to PHI

## Next Steps

- Add more clinical documents to knowledge base
- Implement full care plan generation with LLM
- Build user interface for healthcare providers
- Add real-time patient monitoring integration
- Implement multi-modal RAG (text + medical images)
- Create feedback loop to improve search relevance
- Add support for multiple languages
- Integrate with EHR systems
