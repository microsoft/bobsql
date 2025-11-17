# SQL Server 2025 Demos

This directory contains comprehensive demonstrations of new features and capabilities in SQL Server 2025. Each folder focuses on a specific feature area with detailed examples and step-by-step instructions.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **SQL Server Management Studio (SSMS)**
- **Additional requirements vary by demo** - See individual folder readme files

## Demos Overview

### ABORT_QUERY_EXECUTION
**Automatic Query Cancellation**

Demonstrates the new ABORT_QUERY_EXECUTION hint that allows administrators to automatically cancel problematic queries without modifying application code. Uses Query Store integration to identify and mark specific queries for automatic termination.

**Key Features:**
- Query Store integration
- sp_query_store_set_hints
- Zero application code changes
- Immediate incident response capability

**Use Cases:** Runaway query protection, vendor application issues, ad-hoc query control, multi-tenant isolation

**Prerequisites:** SQL Server 2025, AdventureWorks database, Query Store enabled

[See ABORT_QUERY_EXECUTION/readme.md for full details](./ABORT_QUERY_EXECUTION/readme.md)

---

### AI
**AI and Vector Search Capabilities**

Comprehensive demonstrations of SQL Server 2025's AI features including vector search, embeddings, and semantic similarity. Includes four different AI provider integrations showing flexibility in deployment options.

**Subfolders:**
- **vector_search_azureai** - Azure OpenAI embeddings with text-embedding-3-large model
- **vector_search_openai** - OpenAI-compatible APIs for flexible deployment
- **vector_search_ollama** - Local Ollama embeddings (mxbai-embed-large) for on-premises scenarios
- **vector_search_onnx** - ONNX Runtime for completely offline, high-performance AI

**Key Features:**
- CREATE EXTERNAL MODEL
- AI_GENERATE_EMBEDDINGS() function
- Vector data type and indexes (DiskANN)
- Semantic search capabilities
- Multiple AI provider support

**Use Cases:** Product search, recommendation systems, RAG applications, content discovery, semantic similarity

**Prerequisites:** SQL Server 2025, AdventureWorks database, AI provider (varies by subfolder)

[See AI/readme.md for complete overview](./AI/readme.md)

---

### json
**Native JSON Data Type**

Demonstrates SQL Server 2025's new native JSON data type with automatic validation, improved performance, and dedicated indexing capabilities.

**Key Features:**
- Native json data type with automatic validation
- JSON_VALUE, JSON_ARRAYAGG, JSON_OBJECTAGG functions
- JSON indexing for improved query performance
- JSON_MODIFY for document updates

**Use Cases:** REST APIs, configuration storage, document databases, flexible schemas, log data, e-commerce product catalogs

**Prerequisites:** SQL Server 2025

[See json/readme.md for complete guide](./json/readme.md)

---

### optimized_locking
**Improved Concurrency Through Optimized Locking**

Shows how optimized locking improves concurrency by avoiding lock escalation and reducing lock memory overhead through transaction ID (TID) locking.

**Key Features:**
- Transaction ID locking eliminates lock escalation
- Reduced lock memory consumption
- Improved concurrency for large updates
- Better secondary replica performance (reduced redo)

**Use Cases:** Batch processing, high-concurrency applications, Availability Groups, large table updates, ETL operations

**Prerequisites:** SQL Server 2025 Developer Edition, AdventureWorks database, Accelerated Database Recovery

[See optimized_locking/readme.md for detailed demo](./optimized_locking/readme.md)

---

### regex
**Regular Expression Support**

Demonstrates native regular expression support in T-SQL with REGEXP_LIKE function, enabling powerful pattern matching and validation beyond LIKE capabilities.

**Key Features:**
- REGEXP_LIKE function for pattern matching
- CHECK constraints with regex validation
- Industry-standard regex syntax
- Data validation at database level

**Use Cases:** Email validation, phone number validation, data quality checks, pattern-based searches, format validation

**Prerequisites:** SQL Server 2025

[See regex/readme.md for examples and patterns](./regex/readme.md)

---

### REST
**REST API Integration with Vector Search**

Complete healthcare RAG (Retrieval Augmented Generation) solution combining REST API integration, vector search, and AI embeddings for intelligent care plan generation.

**Key Features:**
- External model integration via REST APIs
- Vector search for knowledge retrieval
- RAG pattern implementation
- PHI (Protected Health Information) separation
- Healthcare knowledge base with patient data

**Use Cases:** Clinical decision support, care plan generation, medical literature search, medication guidance, patient education

**Prerequisites:** SQL Server 2025, Ollama with mxbai-embed-large model

[See REST/readme.md for complete healthcare solution](./REST/readme.md)

---

### tempdb_rg
**TempDB Resource Governor**

Demonstrates controlling tempdb space consumption using Resource Governor workload groups to prevent runaway queries from exhausting tempdb.

**Key Features:**
- GROUP_MAX_TEMPDB_DATA_MB workload group parameter
- Classifier functions for user routing
- Per-workload tempdb space limits
- System protection from tempdb exhaustion

**Use Cases:** Multi-tenant environments, query protection, system stability, capacity planning, shared BI environments

**Prerequisites:** SQL Server 2025

[See tempdb_rg/readme.md for step-by-step setup](./tempdb_rg/readme.md)

---

## SQL Server 2025 Feature Highlights

### AI and Machine Learning
- Native vector data type and DiskANN indexing
- External model integration (Azure OpenAI, OpenAI, Ollama, ONNX)
- AI_GENERATE_EMBEDDINGS() function for embedding generation
- Semantic search capabilities
- Complete RAG pattern support

### Performance and Scalability
- Optimized locking eliminates lock escalation
- DiskANN vector indexes for fast nearest neighbor search
- Improved JSON performance with native data type
- TempDB resource governance
- Query execution control with ABORT_QUERY_EXECUTION

### Developer Productivity
- Native JSON data type with automatic validation
- Regular expression support (REGEXP_LIKE)
- REST API integration for external services
- Enhanced T-SQL functions
- Better data type support

### Manageability and Governance
- Query Store integration for query hints
- Resource Governor tempdb limits
- Improved monitoring and diagnostics
- Better workload management
- Automated query protection

## Getting Started

1. **Choose a demo** based on the feature you want to explore
2. **Navigate to the folder** and read the detailed readme.md file
3. **Check prerequisites** specific to that demo
4. **Follow step-by-step instructions** in each folder's readme
5. **Experiment and learn** by modifying examples to fit your scenarios

## Demo Structure

Each demo folder contains:
- **readme.md** - Comprehensive instructions and explanations
- **Numbered SQL scripts** - Execute in sequential order
- **Setup scripts** - Database and configuration setup (00_*.sql)
- **Demo scripts** - Feature demonstrations (01_*.sql and higher)
- **Cleanup scripts** (when applicable) - Reset environment

## Tips for Success

✅ **Read the readme first** - Each folder has specific instructions and context  
✅ **Follow script order** - Scripts are numbered for proper sequencing  
✅ **Check prerequisites** - Ensure required software and databases are installed  
✅ **Use test environments** - Never run demos on production servers  
✅ **Experiment freely** - Modify examples to understand behavior  
✅ **Monitor resources** - Some demos (AI, large updates) are resource-intensive  

## Feature Comparison

| Feature | Best For | Complexity |
|---------|----------|------------|
| **AI/Vector Search** | Semantic search, RAG applications | Medium-High |
| **ABORT_QUERY_EXECUTION** | Query governance, incident response | Low |
| **Native JSON** | Modern apps, flexible schemas | Low-Medium |
| **Optimized Locking** | High-concurrency workloads | Medium |
| **Regular Expressions** | Data validation, pattern matching | Low |
| **TempDB RG** | Multi-tenant, system protection | Medium |

## Common Scenarios

### Building AI-Powered Applications
1. Start with **AI folder** demos to understand vector search
2. Choose your AI provider (Azure OpenAI, Ollama, ONNX)
3. Explore **REST folder** for complete RAG solution example
4. Use **vector_search_ollama** for local development
5. Graduate to **vector_search_azureai** for production

### Improving Database Concurrency
1. Review **optimized_locking** for lock escalation elimination
2. Combine with appropriate isolation levels
3. Use **tempdb_rg** to prevent resource exhaustion
4. Test with realistic workload patterns

### Implementing Data Validation
1. Use **regex folder** for pattern-based validation
2. Leverage **json folder** for schema validation
3. Implement CHECK constraints with REGEXP_LIKE
4. Combine JSON validation with regex patterns

### Protecting System Resources
1. Deploy **ABORT_QUERY_EXECUTION** for query control
2. Add **tempdb_rg** for resource protection
3. Use Resource Governor for comprehensive governance
4. Monitor and tune based on workload

### Building Modern Applications
1. Use **json folder** for flexible data models
2. Add **REST folder** patterns for API integration
3. Implement **AI features** for intelligent applications
4. Leverage **regex** for robust validation

## Documentation and Resources

- [SQL Server 2025 Documentation](https://aka.ms/sqlserver2025docs)
- [What's New in SQL Server 2025](https://learn.microsoft.com/en-us/sql/sql-server/what-s-new-in-sql-server-2025)
- [Download SQL Server 2025](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- [Download SSMS](https://aka.ms/ssms21)

## Quick Reference Matrix

### By Use Case

| Use Case | Recommended Demos |
|----------|------------------|
| Semantic search | AI (all subfolders) |
| RAG applications | AI + REST |
| Data validation | regex + json |
| Query protection | ABORT_QUERY_EXECUTION + tempdb_rg |
| Concurrency issues | optimized_locking |
| Modern APIs | json + REST |
| On-premises AI | AI/vector_search_ollama, AI/vector_search_onnx |
| Cloud AI | AI/vector_search_azureai, AI/vector_search_openai |

### By Industry

| Industry | Key Demos |
|----------|-----------|
| Healthcare | REST (healthcare RAG), AI (semantic search) |
| E-commerce | AI (product search), json (flexible catalogs) |
| Financial Services | optimized_locking (high concurrency), tempdb_rg |
| SaaS/Multi-tenant | tempdb_rg, ABORT_QUERY_EXECUTION |
| Manufacturing | optimized_locking (batch updates), AI (quality analysis) |

### By Technical Focus

| Focus Area | Relevant Demos |
|------------|---------------|
| AI/ML | AI (all), REST |
| Performance | optimized_locking, tempdb_rg |
| Data Quality | regex, json |
| Governance | ABORT_QUERY_EXECUTION, tempdb_rg |
| Modern Development | json, REST, AI |

## Learning Paths

### Beginner Path
1. **json** - Understand native JSON type
2. **regex** - Learn pattern matching
3. **ABORT_QUERY_EXECUTION** - Query management basics

### Intermediate Path
1. **AI/vector_search_ollama** - Local AI integration
2. **optimized_locking** - Concurrency improvements
3. **tempdb_rg** - Resource governance

### Advanced Path
1. **AI/vector_search_azureai** - Enterprise AI deployment
2. **REST** - Complete RAG solution
3. **AI/vector_search_onnx** - High-performance offline AI

## Support and Feedback

These demos showcase SQL Server 2025 features. For:
- **Issues** - Report via SQL Server feedback channels
- **Questions** - Use SQL Server forums and communities  
- **Feature Requests** - Submit via SSMS feedback tools

## Important Notes

⚠️ **Test Environments Only** - Always test thoroughly before deploying to production  
⚠️ **Performance Testing** - Benchmark with your specific workloads  
⚠️ **Documentation** - Check official docs for latest feature information  
⚠️ **Best Practices** - Follow SQL Server best practices for implementation  

## Contributing

Improvements to these demos are welcome:
- Clearer explanations and documentation
- Additional real-world use cases
- Performance optimization tips
- Best practices and patterns
- Troubleshooting scenarios

---

**Last Updated:** November 2025  
**SQL Server Version:** 2025 Developer Edition  
**Status:** Active

For the latest updates and additional demos, check the repository regularly.
