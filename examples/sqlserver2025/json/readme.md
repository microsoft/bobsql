# JSON Data Type in SQL Server 2025

This demo demonstrates the new native JSON data type in SQL Server 2025, which provides improved performance, validation, and functionality for working with JSON documents.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **SQL Server Management Studio (SSMS)**

## Overview

SQL Server 2025 introduces a native JSON data type that provides:
- Automatic JSON validation on INSERT
- Improved storage efficiency
- Better performance for JSON operations
- Native JSON indexing capabilities
- New JSON functions and operators

## Files

| File | Purpose |
|------|---------|
| `01_json_type_ddl.sql` | Creates database and table with JSON type column |
| `02_json_type_functions.sql` | Demonstrates JSON query functions |
| `03_modify_json.sql` | Shows how to modify JSON documents |
| `04_json_index_ddl.sql` | Creates JSON index on JSON type column |
| `04_json_index_ddl_using_nvarchar.sql` | Alternative: Creates JSON index on NVARCHAR column |
| `05_json_index_show_values.sql` | Displays indexed JSON values |
| `06_use_json_without_index.sql` | Query performance without JSON index |
| `07_create_json_index.sql` | Creates JSON index for performance comparison |
| `08_use_json_with_index.sql` | Query performance with JSON index |

## Step-by-Step Instructions

### Step 1: Create Database and Table with JSON Type
```sql
-- Run: 01_json_type_ddl.sql
```

This script:
- Creates an `orders` database
- Creates a table with a native `json` column
- Inserts sample JSON documents
- Demonstrates automatic JSON validation on INSERT

**Key Feature:** Invalid JSON will be rejected automatically - no need for manual validation!

### Step 2: Work with JSON Functions
```sql
-- Run: 02_json_type_functions.sql
```

Demonstrates core JSON functions:
- **JSON_VALUE()** - Extract scalar values from JSON
- **JSON_ARRAYAGG()** - Aggregate rows into a JSON array
- **JSON_OBJECTAGG()** - Create key-value JSON objects

### Step 3: Modify JSON Documents
```sql
-- Run: 03_modify_json.sql
```

Shows how to:
- Update specific JSON properties
- Add new properties to existing JSON documents
- Remove properties from JSON documents
- Perform complex JSON modifications

### Step 4: Create JSON Index
```sql
-- Run: 04_json_index_ddl.sql
```

Creates a JSON index on the native JSON column for improved query performance.

**Alternative:** If you want to see how JSON indexing works with traditional NVARCHAR columns:
```sql
-- Run: 04_json_index_ddl_using_nvarchar.sql
```

### Step 5: Explore JSON Index Values
```sql
-- Run: 05_json_index_show_values.sql
```

Displays the indexed values to understand how JSON indexing works internally.

### Step 6: Performance Comparison

**Without Index:**
```sql
-- Run: 06_use_json_without_index.sql
```

Execute queries against JSON data without an index and note the performance.

**Create Index:**
```sql
-- Run: 07_create_json_index.sql
```

Creates the JSON index.

**With Index:**
```sql
-- Run: 08_use_json_with_index.sql
```

Execute the same queries with the index and compare performance improvements.

## What You'll Learn

- How to define tables with native JSON data type
- Automatic JSON validation on INSERT operations
- Using JSON query and manipulation functions
- Creating and using JSON indexes for performance
- Performance differences between indexed and non-indexed JSON queries
- Best practices for storing and querying JSON data

## Key Concepts

**Native JSON Type:** A dedicated data type for JSON that provides validation, optimized storage, and better performance compared to storing JSON in NVARCHAR columns.

**JSON Validation:** Automatic validation ensures only valid JSON documents can be stored, preventing data quality issues.

**JSON Index:** A specialized index that improves query performance when searching or filtering JSON properties.

**JSON Functions:** Built-in functions like JSON_VALUE, JSON_QUERY, JSON_MODIFY, JSON_ARRAYAGG, and JSON_OBJECTAGG for working with JSON data.

## Benefits of Native JSON Type

✅ **Automatic Validation** - Invalid JSON is rejected on INSERT  
✅ **Better Performance** - Optimized storage and query execution  
✅ **Type Safety** - Ensures data integrity at the database level  
✅ **Improved Indexing** - Native support for JSON indexing  
✅ **Standards Compliant** - Follows JSON standards strictly  

## Use Cases

- **REST APIs** - Store API request/response data
- **Configuration Data** - Flexible schema for settings and configuration
- **Log Data** - Store structured log entries
- **Document Storage** - Semi-structured document management
- **E-commerce** - Product catalogs with varying attributes
- **IoT Data** - Sensor readings with different schemas

## Performance Tips

1. **Use JSON Indexes** - For frequently queried JSON properties
2. **Extract to Columns** - For critical properties that need optimal performance
3. **Validate Early** - Let SQL Server validate JSON at INSERT time
4. **Right-Size Queries** - Only extract the JSON properties you need
5. **Consider Computed Columns** - For frequently accessed JSON properties

## Troubleshooting

**JSON Validation Error:** Ensure your JSON is properly formatted with valid syntax.

**Index Not Used:** Check that your query predicates match the indexed JSON paths.

**Performance Issues:** Consider extracting frequently queried JSON properties to regular columns.

## Next Steps

- Combine JSON with other SQL Server features (Full-Text Search, etc.)
- Implement hybrid schemas (relational + JSON)
- Build REST APIs backed by JSON storage
- Migrate from NVARCHAR JSON storage to native JSON type
- Explore JSON with computed columns for optimal performance
