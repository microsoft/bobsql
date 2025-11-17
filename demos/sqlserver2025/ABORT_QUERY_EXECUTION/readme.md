# ABORT_QUERY_EXECUTION Query Hint in SQL Server 2025

This demo demonstrates the new ABORT_QUERY_EXECUTION hint in SQL Server 2025, which allows administrators to automatically cancel problematic queries without modifying application code.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **AdventureWorks Database** - [Download AdventureWorks2022.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak)
- **SQL Server Management Studio (SSMS)**

## Overview

The ABORT_QUERY_EXECUTION hint is a powerful feature for database administrators to handle runaway queries that cause performance issues. Instead of modifying application code or requiring application restarts, administrators can mark specific queries in Query Store to be automatically aborted on subsequent executions.

**Key Benefits:**
- No application code changes required
- Immediate protection from problematic queries
- Works through Query Store integration
- Can be enabled/disabled without application downtime
- Helps maintain system stability during incidents

## Files

| File | Purpose |
|------|---------|
| `01_restore_adventureworks.sql` | Restores the AdventureWorks sample database |
| `02_enablequerystore.sql` | Enables Query Store for the AdventureWorks database |
| `03_poorquery.sql` | Example of a poorly performing query |
| `04_findtopdurationquereis.sql` | Finds top queries by duration using Query Store |
| `05_setabortqueryhint.sql` | Sets ABORT_QUERY_EXECUTION hint for a specific query |
| `06_clearabortqueryhint.sql` | Removes ABORT_QUERY_EXECUTION hint from a query |

## Step-by-Step Instructions

### Step 1: Restore AdventureWorks Database
```sql
-- Run: 01_restore_adventureworks.sql
```

Restores the AdventureWorks2022 sample database.

**Note:** You may need to edit the file paths in the script to match your backup file location and database/log file paths.

### Step 2: Enable Query Store
```sql
-- Run: 02_enablequerystore.sql
```

Enables Query Store for the AdventureWorks database. Query Store is required for the ABORT_QUERY_EXECUTION feature to work as it tracks query execution history and stores the abort hint.

### Step 3: Execute the Problematic Query
```sql
-- Run: 03_poorquery.sql
```

This script contains a poorly performing query that:
- Takes 12-15 seconds to complete
- Uses inefficient subqueries in the SELECT list
- Performs a CROSS JOIN creating a large result set
- Has multiple aggregations causing high CPU usage
- Demonstrates the type of query you'd want to abort

**Scenario:** This query was built to fulfill a business requirement: "The company needs to understand which products are performing well, identify high-value customers, and analyze sales patterns over time. The report should include metrics such as average unit price, total sales, order count, and the most recent purchase date for each customer. Additionally, the company wants to see the number of reviews for each product to gauge customer satisfaction."

While the query works, it's poorly optimized and represents a situation where:
- The application cannot be quickly modified
- There's lack of control over what queries users can execute
- Immediate action is needed to protect system performance

Let the query complete so it's captured in Query Store.

### Step 4: Find the Query in Query Store
```sql
-- Run: 04_findtopdurationquereis.sql
```

This query searches Query Store for the top queries by total duration. The poor query from Step 3 should appear at the top of the results.

**Important Actions:**
1. Verify the `query_sql_text` column matches the query from `03_poorquery.sql`
2. Note the `query_id` value - you'll need this for the next step

The query shows:
- Query ID
- SQL text
- Execution count
- Average duration
- Total duration
- Last execution time

### Step 5: Set ABORT_QUERY_EXECUTION Hint
```sql
-- Run: 05_setabortqueryhint.sql
```

**Before running:** Edit the script and replace the `@query_id` value with the actual query ID from Step 4.

This script uses `sp_query_store_set_hints` to set the ABORT_QUERY_EXECUTION hint for the specific query. Once set, any future execution of this query will be immediately aborted.

### Step 6: Test the Abort Behavior
```sql
-- Run: 03_poorquery.sql (again)
```

Execute the same query from Step 3 again. This time, instead of running for 12-15 seconds, the query will be immediately aborted with the following error:

```
Msg 8778, Level 16, State 1, Line 1
Query execution has been aborted because the ABORT_QUERY_EXECUTION hint was specified
```

This demonstrates how the hint protects your system from the problematic query without any application changes!

### Step 7: Clear the Abort Hint (Optional)
```sql
-- Run: 06_clearabortqueryhint.sql
```

**Before running:** Edit the script and replace the `@query_id` value with the query ID.

This removes the ABORT_QUERY_EXECUTION hint, allowing the query to run normally again. Use this when:
- The query has been fixed in the application
- You want to test if performance issues are resolved
- The query is no longer problematic

## What You'll Learn

- How to enable and use Query Store
- Identifying problematic queries using Query Store DMVs
- Setting query hints through sp_query_store_set_hints
- Using ABORT_QUERY_EXECUTION to protect system performance
- Managing query hints without application code changes
- Incident response techniques for runaway queries

## Key Concepts

**Query Store:** A feature that automatically captures query execution history, plans, and runtime statistics, enabling better performance troubleshooting.

**ABORT_QUERY_EXECUTION Hint:** A query hint that causes SQL Server to immediately terminate a query's execution, preventing it from consuming resources.

**sp_query_store_set_hints:** A system stored procedure that allows setting query hints for specific queries tracked in Query Store.

**Query ID:** A unique identifier assigned by Query Store to each distinct query text.

## Use Cases

**Incident Response:**
- Production system experiencing performance issues
- Identified a specific query causing problems
- Need immediate relief while development team fixes the code

**Vendor Applications:**
- Cannot modify third-party application code
- Vendor query causing performance degradation
- Need protection until vendor provides a fix

**Ad-Hoc Queries:**
- Users running inefficient ad-hoc queries
- Cannot control what queries are submitted
- Need to prevent specific problematic patterns

**Multi-Tenant Environments:**
- One tenant's query impacting others
- Quick isolation without affecting other tenants
- Maintain SLA compliance

**Testing and Validation:**
- Temporarily disable specific queries during testing
- Validate application behavior when queries fail
- Test error handling logic

## Benefits

✅ **Zero Application Changes** - No code deployment required  
✅ **Immediate Effect** - Protection starts on next execution  
✅ **Reversible** - Can be removed when issue is resolved  
✅ **Targeted** - Only affects the specific problematic query  
✅ **Query Store Integration** - Leverages existing infrastructure  
✅ **Audit Trail** - Query Store tracks when hints are applied  

## Best Practices

1. **Document the Query ID** - Keep a record of which queries have abort hints and why
2. **Set Up Alerts** - Monitor for error 8778 to track aborted executions
3. **Communicate with Teams** - Inform application teams when hints are applied
4. **Plan for Resolution** - Use abort hints as temporary measures, not permanent solutions
5. **Test in Non-Production** - Validate behavior before applying in production
6. **Review Regularly** - Periodically review and remove hints that are no longer needed

## Troubleshooting

**Hint Not Taking Effect:**
- Verify Query Store is enabled and in READ_WRITE mode
- Confirm you're using the correct query_id
- Check that the query text exactly matches (whitespace matters)
- Ensure sp_query_store_set_hints executed successfully

**Query Still Running:**
- The hint only affects new executions, not already-running queries
- Use KILL command for currently executing sessions
- Verify the hint was applied using sys.query_store_query_hints

**Cannot Find Query in Query Store:**
- Ensure Query Store is enabled before running the query
- Check Query Store size limits (may have been evicted)
- Verify query actually executed (check sys.query_store_runtime_stats)

## Next Steps

- Identify other problematic queries in your environment
- Implement monitoring for query performance degradation
- Create runbooks for applying abort hints during incidents
- Establish processes for reviewing and removing hints
- Train teams on when and how to use this feature
