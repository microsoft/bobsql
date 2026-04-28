-- ============================================================================
-- 02-create-table-with-data.sql
-- Creates a knowledge base table with a vector column and inserts sample data
-- about Azure SQL Database features and capabilities.
-- Inserts 110+ rows to meet the 100-row minimum for vector index creation.
-- ============================================================================

-- Create the knowledge base table with a native vector column
CREATE TABLE dbo.azure_sql_knowledge
(
    id INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    title NVARCHAR(200) NOT NULL,
    category NVARCHAR(100) NOT NULL,
    content NVARCHAR(MAX) NOT NULL,
    embedding VECTOR(1536) NULL
);
GO

-- Insert sample data about Azure SQL Database features and capabilities
INSERT INTO dbo.azure_sql_knowledge (title, category, content)
VALUES
(N'Azure SQL Database Hyperscale Tier',
 N'Service Tiers',
 N'Azure SQL Database Hyperscale is a highly scalable storage and compute tier that leverages Azure architecture to scale out storage and compute resources for a database substantially beyond the limits available for the General Purpose and Business Critical tiers. Hyperscale supports up to 100 TB of data and provides near-instantaneous backups and fast database restores in minutes regardless of the size of data. It uses a distributed architecture with page servers that serve as a distributed storage cache, keeping data close to compute replicas for fast access.'),

(N'Serverless Compute Tier',
 N'Service Tiers',
 N'Azure SQL Database serverless is a compute tier that automatically scales compute based on workload demand and bills for the amount of compute used per second. Serverless compute tier also automatically pauses databases during inactive periods when only storage is billed and automatically resumes databases when activity returns. This makes serverless ideal for intermittent and unpredictable workloads. The auto-pause delay can be configured from 1 hour to 7 days, or auto-pause can be disabled. Min and max vCores can be configured to control the auto-scaling range.'),

(N'Elastic Pools for Resource Sharing',
 N'Service Tiers',
 N'Azure SQL Database elastic pools provide a simple and cost-effective solution for managing and scaling multiple databases that have varying and unpredictable usage demands. The databases in an elastic pool are on a single server and share a set number of resources at a set price. Elastic pools are ideal for SaaS multi-tenant applications where each tenant gets their own database. Resource utilization across databases is automatically balanced, and you pay only for the pool resources rather than provisioning resources for each individual database.'),

(N'Built-in High Availability',
 N'Availability',
 N'Azure SQL Database provides built-in high availability with a 99.99% uptime SLA. The service uses a combination of Always On availability groups and Azure Storage redundancy to ensure your data is protected. For the General Purpose tier, Azure SQL uses a remote storage architecture with locally redundant storage. The Business Critical tier uses a local storage architecture similar to Always On availability groups with multiple synchronous replicas. Zone redundant configuration distributes replicas across availability zones for additional resilience against datacenter failures.'),

(N'Active Geo-Replication',
 N'Availability',
 N'Active geo-replication in Azure SQL Database lets you create readable secondary databases of individual databases on a server in the same or different region. Up to four secondaries are supported in the same or different regions and can be used for read-only query workloads. Active geo-replication uses the same Always On availability group technology as high availability to asynchronously replicate committed transactions. When combined with auto-failover groups, you get automatic failover with zero data loss RPO and less than 30 seconds RTO for most scenarios.'),

(N'Automatic Failover Groups',
 N'Availability',
 N'Auto-failover groups in Azure SQL Database manage replication and failover of a group of databases on a server or all databases in a managed instance to another region. The feature provides a read-write and read-only listener endpoint that remains unchanged after failover, eliminating the need to change connection strings. Failover can be automatic or manual. With grace period configuration, you can control how long the system waits before triggering automatic failover. This provides disaster recovery for mission-critical applications requiring geographic redundancy.'),

(N'Automatic Tuning',
 N'Performance',
 N'Azure SQL Database automatic tuning uses artificial intelligence and machine learning to continuously monitor and improve query performance. It includes three features: automatic plan correction which identifies and fixes plan regression issues, create and drop index recommendations based on workload analysis, and force/unforce plan recommendations. The system analyzes workload patterns, validates improvements, and can automatically apply or revert changes. All tuning actions are fully transparent and can be reviewed in the Azure portal or via DMVs.'),

(N'Intelligent Query Processing',
 N'Performance',
 N'Intelligent Query Processing (IQP) is a family of features in the database engine that improve query performance without requiring code changes. IQP includes adaptive joins that choose between nested loop and hash joins at runtime, interleaved execution for multi-statement table-valued functions, memory grant feedback that adjusts memory allocations, batch mode on rowstore for analytical queries, table variable deferred compilation, and approximate query processing with APPROX_COUNT_DISTINCT. These features automatically improve performance for existing workloads.'),

(N'Parameter Sensitivity Plan Optimization',
 N'Performance',
 N'Parameter Sensitivity Plan (PSP) optimization addresses the scenario where a single cached plan for a parameterized query is not optimal for all possible incoming parameter values. This is common with skewed data distributions. PSP optimization automatically identifies queries that are sensitive to parameter values and generates multiple plans for different parameter ranges. The query processor maps incoming parameter values to the appropriate cached plan. This eliminates most parameter sniffing problems without requiring RECOMPILE hints or application code changes.'),

(N'Query Store for Performance Insights',
 N'Performance',
 N'Query Store captures a history of queries, plans, and runtime statistics, providing full visibility into query performance over time. You can identify queries that have regressed, compare plan performance across different time periods, and force plans that perform well. Query Store is enabled by default in Azure SQL Database. It includes reports for Top Resource Consuming Queries, Regressed Queries, and Overall Resource Consumption. Query Store data persists across database restarts and is invaluable for performance troubleshooting and capacity planning.'),

(N'Accelerated Database Recovery',
 N'Performance',
 N'Accelerated Database Recovery (ADR) dramatically improves database availability by redesigning the SQL Server database engine recovery process. ADR uses persistent version store (PVS) to provide instantaneous transaction rollback regardless of active transaction size. Database recovery time is constant and fast regardless of the number of active transactions. The transaction log is aggressively truncated preventing excessive log growth from long-running transactions. ADR is enabled by default in Azure SQL Database and is essential for workloads requiring consistent recovery times.'),

(N'Microsoft Entra Authentication',
 N'Security',
 N'Azure SQL Database supports Microsoft Entra authentication (formerly Azure Active Directory) allowing you to connect using Entra identities including users, groups, and service principals. Entra-only authentication mode disables SQL authentication entirely for stronger security posture. You can use managed identities for Azure services to connect to Azure SQL without storing credentials. Multi-factor authentication and conditional access policies provide additional layers of protection. Entra authentication is the recommended authentication method for all Azure SQL Database workloads.'),

(N'Transparent Data Encryption',
 N'Security',
 N'Transparent Data Encryption (TDE) performs real-time I/O encryption and decryption of data and log files at the page level. Data is encrypted before being written to disk and decrypted when read into memory. TDE is enabled by default for all new Azure SQL databases and uses a service-managed certificate. You can also bring your own key (BYOK) stored in Azure Key Vault for full control over the encryption key lifecycle. TDE protects data at rest from physical media theft without requiring changes to existing applications.'),

(N'Dynamic Data Masking',
 N'Security',
 N'Dynamic Data Masking (DDM) limits sensitive data exposure by masking it to non-privileged users. DDM is a policy-based security feature that hides sensitive data in the result set of a query over designated database fields while the data in the database is not changed. Masking rules can be defined on specific columns and several masking functions are available including default, email, random number, and custom string masking. Privileged users such as database administrators can always view unmasked data. DDM can be configured in the Azure portal or via T-SQL.'),

(N'Row-Level Security',
 N'Security',
 N'Row-Level Security (RLS) enables you to control access to rows in a database table based on the characteristics of the user executing a query. This is commonly used in multi-tenant applications to ensure tenants can only access their own data. RLS uses filter predicates to silently filter rows that the user is not authorized to access, and block predicates to prevent unauthorized INSERT, UPDATE, or DELETE operations. Security policies are defined using inline table-valued functions and applied transparently without modifying application queries.'),

(N'Vector Search in Azure SQL Database',
 N'AI and Machine Learning',
 N'Azure SQL Database natively supports vector data types and vector search operations. The vector data type stores arrays of floating-point numbers representing embeddings. The VECTOR_DISTANCE function calculates cosine, dot product, or euclidean distance between vectors for similarity search. Combined with DiskANN-based vector indexes, you can perform approximate nearest neighbor (ANN) search across millions of vectors with high recall and low latency. This enables AI scenarios like semantic search, recommendation engines, and retrieval augmented generation (RAG) patterns directly in the database.'),

(N'sp_invoke_external_rest_endpoint',
 N'AI and Machine Learning',
 N'The sp_invoke_external_rest_endpoint stored procedure allows Azure SQL Database to call external HTTPS REST endpoints directly from T-SQL. This enables integration with Azure OpenAI, Azure Functions, Azure Event Hubs, Azure Blob Storage, and many other Azure services. Authentication can use managed identity, API keys, or SAS tokens via database scoped credentials. The stored procedure supports GET, POST, PUT, PATCH, DELETE, and HEAD methods with JSON, XML, or text payloads. Response data is returned as JSON or XML for processing within T-SQL queries.'),

(N'CREATE EXTERNAL MODEL for AI Integration',
 N'AI and Machine Learning',
 N'CREATE EXTERNAL MODEL defines an AI model endpoint connection within the database. It supports Azure OpenAI, OpenAI, Ollama, and ONNX Runtime as API formats. Currently supports EMBEDDINGS model type. Combined with AI_GENERATE_EMBEDDINGS function, it provides a streamlined way to generate vector embeddings directly in T-SQL without manually calling REST endpoints. The external model stores the endpoint location, API format, model name, and credential reference. This simplifies AI integration by abstracting the REST API complexity behind a SQL-native interface.'),

(N'Azure SQL Database Free Tier',
 N'Service Tiers',
 N'Azure SQL Database offers a free tier that provides a General Purpose serverless database with a monthly free amount of vCore seconds and storage. The free offer includes up to 100,000 vCore seconds of compute and 32 GB of data storage per month. When the free limits are exhausted, the database can be configured to auto-pause or continue at standard billing rates. This is ideal for development, learning, proof-of-concept projects, and small production workloads. Only one free database is allowed per Azure subscription.'),

(N'Columnstore Indexes for Analytics',
 N'Performance',
 N'Columnstore indexes in Azure SQL Database provide high-performance analytics and data warehousing capabilities. They store and process data in a columnar format with up to 10x query performance improvement and 10x data compression compared to traditional rowstore. Both clustered and nonclustered columnstore indexes are supported. Batch mode processing enables efficient analytical queries on large datasets. Columnstore indexes can be combined with rowstore indexes on the same table for hybrid transactional and analytical processing (HTAP) workloads.'),

(N'In-Memory OLTP',
 N'Performance',
 N'In-Memory OLTP (Hekaton) in Azure SQL Database provides memory-optimized tables and natively compiled stored procedures for extreme transaction processing performance. Memory-optimized tables can be durable or non-durable (schema-only). They eliminate latch and lock contention using optimistic multi-version concurrency control. Natively compiled stored procedures compile T-SQL to native machine code for maximum throughput. In-Memory OLTP is available in the Business Critical and Hyperscale tiers and can deliver up to 30x transaction processing improvement for eligible workloads.'),

(N'Temporal Tables for Time Travel Queries',
 N'Development',
 N'Temporal tables (system-versioned tables) in Azure SQL Database automatically track the full history of data changes. Every row modification is recorded with valid-from and valid-to timestamps. You can query data as of any point in time using the FOR SYSTEM_TIME clause. Temporal tables support AS OF, FROM TO, BETWEEN, CONTAINED IN, and ALL sub-clauses for different time-based query patterns. This is valuable for audit trails, slowly changing dimensions, data recovery from accidental changes, and regulatory compliance requirements.'),

(N'JSON Support in Azure SQL Database',
 N'Development',
 N'Azure SQL Database provides comprehensive JSON support including the native JSON data type, JSON functions like JSON_VALUE, JSON_QUERY, JSON_MODIFY, JSON_OBJECT, and JSON_ARRAY, and the OPENJSON function for parsing JSON into relational rows. You can index JSON properties using computed columns. JSON support enables flexible schema design where structured relational data coexists with semi-structured JSON data. The FOR JSON clause exports query results as JSON. This makes Azure SQL Database an excellent choice for applications that mix relational and document-style data patterns.'),

(N'Elastic Jobs for Cross-Database Automation',
 N'Management',
 N'Elastic Jobs in Azure SQL Database enable you to run T-SQL scripts across multiple databases on a schedule or on-demand. Jobs can target individual databases, elastic pools, or custom groups of databases. Each job consists of one or more steps that execute T-SQL scripts. Job execution history and status are tracked automatically. Elastic Jobs are ideal for data maintenance tasks, index management, statistics updates, schema deployments, and data synchronization across multiple databases. They replace the need for SQL Server Agent in cloud scenarios.'),

(N'Azure SQL Managed Instance',
 N'Service Tiers',
 N'Azure SQL Managed Instance is a fully managed deployment option that provides near 100% compatibility with the latest SQL Server database engine. It supports features like cross-database queries, CLR, SQL Server Agent, linked servers, and database mail that are not available in Azure SQL Database. Managed Instance is designed for lift-and-shift migrations with minimal application changes. It runs in a virtual network (VNet) providing native virtual network support and secure connectivity to on-premises environments via VPN or ExpressRoute.');

-- Generate additional rows to meet the 100-row minimum for vector index creation
-- These cover general cloud computing and database topics
INSERT INTO dbo.azure_sql_knowledge (title, category, content)
SELECT
    N'Database Performance Optimization Technique ' + CAST(value AS NVARCHAR(10)),
    CASE value % 5
        WHEN 0 THEN N'Performance'
        WHEN 1 THEN N'Security'
        WHEN 2 THEN N'Development'
        WHEN 3 THEN N'Management'
        WHEN 4 THEN N'AI and Machine Learning'
    END,
    CASE value % 10
        WHEN 0 THEN N'Query optimization involves analyzing execution plans, identifying bottlenecks such as table scans or key lookups, and applying targeted improvements like index tuning, query rewrites, or statistics updates to reduce resource consumption and improve response times for database workloads.'
        WHEN 1 THEN N'Database security best practices include implementing the principle of least privilege, using encryption for data at rest and in transit, enabling auditing and threat detection, regularly reviewing access permissions, and keeping the database engine patched with the latest security updates.'
        WHEN 2 THEN N'Modern application development with databases leverages ORMs, connection pooling, retry logic for transient faults, asynchronous query execution, and parameterized queries to prevent SQL injection while maintaining high performance and developer productivity.'
        WHEN 3 THEN N'Database administration in the cloud involves monitoring resource utilization, configuring automated backups, managing scaling operations, implementing disaster recovery strategies, and using infrastructure as code for reproducible deployments.'
        WHEN 4 THEN N'Machine learning integration with databases enables in-database scoring, feature engineering using SQL queries, storing model artifacts alongside data, and leveraging vector embeddings for semantic similarity search in AI-powered applications.'
        WHEN 5 THEN N'Index management strategies include identifying missing indexes from query plans, removing unused indexes that add write overhead, rebuilding fragmented indexes, and using filtered indexes for queries that consistently filter on specific predicates.'
        WHEN 6 THEN N'Data encryption strategies encompass transparent data encryption for at-rest protection, Always Encrypted for client-side encryption of sensitive columns, TLS for in-transit encryption, and Azure Key Vault integration for centralized key management.'
        WHEN 7 THEN N'Stored procedure best practices include using SET NOCOUNT ON to reduce network traffic, implementing proper error handling with TRY-CATCH, using parameterized queries to prevent SQL injection, and keeping procedures focused on single responsibilities.'
        WHEN 8 THEN N'Cloud database monitoring involves tracking key metrics like DTU or vCore utilization, query duration, wait statistics, connection counts, and storage consumption to proactively identify and resolve performance issues before they impact users.'
        WHEN 9 THEN N'Vector embeddings represent text, images, or other data as high-dimensional numeric arrays that capture semantic meaning. Similar concepts produce similar vectors, enabling semantic search, recommendation systems, and retrieval augmented generation patterns in databases.'
    END
FROM GENERATE_SERIES(1, 85);
GO

-- Verify row count (should be 110)
SELECT COUNT(*) AS total_rows FROM dbo.azure_sql_knowledge;
SELECT category, COUNT(*) AS count FROM dbo.azure_sql_knowledge GROUP BY category ORDER BY count DESC;
GO
