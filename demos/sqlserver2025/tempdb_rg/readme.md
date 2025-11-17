# TempDB Resource Governor in SQL Server 2025

This demo demonstrates the new TempDB Resource Governor feature in SQL Server 2025, which allows you to limit tempdb space usage per workload group to prevent runaway queries from consuming all tempdb space.

## Prerequisites

- **SQL Server 2025 Developer Edition** - [Download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)
- **SQL Server Management Studio (SSMS)**

## Overview

SQL Server 2025 introduces the ability to limit tempdb data file space consumption using Resource Governor. This feature helps:

- Prevent single queries from filling tempdb
- Protect other workloads from tempdb space issues
- Improve multi-tenant environments where users share resources
- Provide predictable tempdb space allocation
- Avoid system-wide outages due to tempdb exhaustion

## Files

| File | Purpose |
|------|---------|
| `01_setempdbsize.sql` | Sets tempdb data and log file sizes |
| `02_checktempdbsize.sql` | Verifies current tempdb size configuration |
| `03_iknowsql.sql` | Creates login and user for "good" user scenario |
| `04_processdata.sql` | Sample query that uses moderate tempdb space |
| `05_tempdb_session_usage.sql` | Monitors tempdb space usage by session |
| `06_createbigdata.sql` | Creates large dataset for testing |
| `07_guyinacubelogin.sql` | Creates login for "problematic" user scenario |
| `08_guyinacubepoorquery.sql` | Query that consumes excessive tempdb space |
| `09_setuprg.sql` | Configures Resource Governor workload group with tempdb limit |
| `10_classifierfunction.sql` | Creates classifier function to route users to workload groups |
| `11_checktempdbrg.sql` | Verifies Resource Governor tempdb configuration |
| `12_disablerg.sql` | Disables Resource Governor |
| `13_setempdbdefault.sql` | Resets tempdb to default settings |

## Step-by-Step Instructions

### Step 1: Configure TempDB Size
```sql
-- Run: 01_setempdbsize.sql
```

Sets tempdb data files to 64MB each (8 files = 512MB total) and log file to 1000MB.

**Important:** You must restart SQL Server for tempdb size changes to take effect.

### Step 2: Verify TempDB Configuration
```sql
-- Run: 02_checktempdbsize.sql
```

Confirms the tempdb data and log file sizes are configured correctly.

### Step 3: Create "Good" User
```sql
-- Run: 03_iknowsql.sql
```

Creates login `iknowsql` and user with appropriate permissions. This represents a user who writes efficient queries.

### Step 4: Test Moderate TempDB Usage
```sql
-- Run: 04_processdata.sql
```

Execute this as the `iknowsql` user to see normal tempdb usage patterns.

### Step 5: Monitor TempDB Usage
```sql
-- Run: 05_tempdb_session_usage.sql
```

Keep this query running in a separate window to monitor real-time tempdb space usage by session. This will help you see the Resource Governor limits in action.

### Step 6: Create Large Test Dataset
```sql
-- Run: 06_createbigdata.sql
```

Creates a large table with sample data for testing tempdb-intensive queries.

### Step 7: Create "Problematic" User
```sql
-- Run: 07_guyinacubelogin.sql
```

Creates login `guyinacube` representing a user who may run inefficient queries that consume excessive tempdb space.

### Step 8: Test Query Without Resource Governor

First, execute the query WITHOUT Resource Governor:
```sql
-- Run: 08_guyinacubepoorquery.sql (as guyinacube user)
```

This query performs multiple sorts and aggregations, consuming significant tempdb space. Without Resource Governor, this query will succeed but may consume hundreds of MB of tempdb space.

Monitor tempdb usage using `05_tempdb_session_usage.sql` in another window.

### Step 9: Configure Resource Governor with TempDB Limit
```sql
-- Run: 09_setuprg.sql
```

Creates a workload group `GroupforUsersWhoDontKnowSQL` with:
- **GROUP_MAX_TEMPDB_DATA_MB = 100** - Limits tempdb data usage to 100MB

This configuration will protect tempdb from being filled by runaway queries.

### Step 10: Create Classifier Function
```sql
-- Run: 10_classifierfunction.sql
```

Creates a classifier function that:
- Routes `guyinacube` user to the restricted workload group
- Routes other users to the default group

**Important:** After creating the classifier function, Resource Governor must be reconfigured with the classifier, and connections must be reestablished for it to take effect.

### Step 11: Verify Resource Governor Configuration
```sql
-- Run: 11_checktempdbrg.sql
```

Confirms:
- Resource Governor is enabled
- Workload group has tempdb limit configured
- Classifier function is active

### Step 12: Test Query WITH Resource Governor

Now reconnect as `guyinacube` user and re-execute:
```sql
-- Run: 08_guyinacubepoorquery.sql (as guyinacube user)
```

This time, the query will fail with an error:
```
Msg 1105, Level 17, State 2
Could not allocate space for object in database 'tempdb' because the 
'GroupforUsersWhoDontKnowSQL' workload group has exceeded its quota for 
tempdb data space. The maximum allowed is 100 MB.
```

This demonstrates Resource Governor protecting tempdb from excessive usage!

Meanwhile, the `iknowsql` user can still run queries normally since they're not in the restricted workload group.

### Step 13: Cleanup (Optional)

**Disable Resource Governor:**
```sql
-- Run: 12_disablerg.sql
```

**Reset TempDB:**
```sql
-- Run: 13_setempdbdefault.sql
```

Then restart SQL Server to apply default tempdb settings.

## What You'll Learn

- How to configure Resource Governor with tempdb limits
- Creating workload groups with tempdb space restrictions
- Building classifier functions to route users to workload groups
- Monitoring tempdb space usage by session
- Protecting tempdb from runaway queries
- Understanding error messages when tempdb limits are exceeded
- Best practices for multi-tenant SQL Server environments

## Key Concepts

**Resource Governor:** SQL Server feature that enables control over resource consumption by different workloads.

**Workload Group:** A container for session requests with similar resource requirements and policies.

**Classifier Function:** A user-defined function that determines which workload group a session should use based on connection properties.

**GROUP_MAX_TEMPDB_DATA_MB:** New SQL Server 2025 parameter that limits tempdb data file space usage for a workload group.

**TempDB:** System database used for temporary objects, sort operations, hash joins, and other intermediate results.

## Use Cases

- **Multi-Tenant SaaS** - Prevent one tenant from consuming all tempdb
- **Shared BI Environments** - Limit ad-hoc query impact
- **Development/Test Servers** - Protect against poorly written queries
- **Mixed Workloads** - Ensure critical workloads aren't affected by batch jobs
- **Query Tuning** - Force developers to optimize queries
- **Capacity Planning** - Control resource usage predictably

## Benefits

✅ **System Stability** - Prevent tempdb exhaustion outages  
✅ **Workload Isolation** - Protect critical workloads  
✅ **Predictable Performance** - Control resource allocation  
✅ **Multi-Tenant Support** - Fair resource sharing  
✅ **Query Optimization** - Encourages efficient queries  
✅ **Cost Control** - Prevent resource waste  

## Monitoring Queries

**Check TempDB Usage by Session:**
```sql
SELECT 
    session_id,
    request_id,
    user_objects_alloc_page_count,
    user_objects_dealloc_page_count,
    internal_objects_alloc_page_count,
    internal_objects_dealloc_page_count
FROM sys.dm_db_task_space_usage
WHERE session_id > 50;
```

**Check Workload Group Assignment:**
```sql
SELECT 
    s.session_id,
    s.login_name,
    r.group_id,
    wg.name AS workload_group
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
LEFT JOIN sys.resource_governor_workload_groups wg ON r.group_id = wg.group_id
WHERE s.session_id > 50;
```

**Check Resource Governor Stats:**
```sql
SELECT 
    name,
    total_request_count,
    total_queued_request_count,
    total_cpu_limit_violation_count
FROM sys.dm_resource_governor_workload_groups;
```

## Design Considerations

**Setting Limits:**
- Analyze typical tempdb usage patterns
- Set limits appropriate for workload types
- Leave headroom for legitimate large queries
- Consider peak usage scenarios

**Classifier Function:**
- Keep logic simple and fast (executes for every connection)
- Consider login name, application name, or host name
- Test thoroughly before deploying to production
- Document classification rules

**Workload Groups:**
- Create groups based on workload characteristics
- Consider multiple tiers (small, medium, large)
- Balance protection vs. functionality
- Review and adjust limits based on monitoring

## Troubleshooting

**Query Failing with Tempdb Quota Error:**
- Check if query can be optimized to use less tempdb
- Consider moving user to different workload group
- Adjust GROUP_MAX_TEMPDB_DATA_MB if limit too restrictive
- Use OPTION (RECOMPILE) or statistics updates if plan is inefficient

**Classifier Function Not Working:**
- Verify Resource Governor is enabled
- Confirm classifier function is registered
- New connections needed for changes to take effect
- Check for errors in classifier function logic

**Unable to Set TempDB Size:**
- Must restart SQL Server for tempdb changes
- Check disk space availability
- Verify file paths exist and are accessible

**Resource Governor Not Limiting:**
- Ensure Resource Governor is enabled (ALTER RESOURCE GOVERNOR RECONFIGURE)
- Verify session is classified correctly
- Check workload group configuration

## Performance Impact

- **Classifier Function** - Minimal overhead, executes once per connection
- **TempDB Monitoring** - Negligible overhead, tracked by SQL Server
- **Enforcement** - No performance penalty when under limits
- **Exceeded Limits** - Query terminates quickly with error

## Next Steps

- Implement Resource Governor in test environments
- Analyze workload patterns and set appropriate limits
- Create comprehensive classifier function for your environment
- Monitor and tune workload group settings
- Combine with CPU and memory Resource Governor settings
- Implement alerting for tempdb quota violations
- Document policies and communicate to users
- Build self-service tools for users to check their usage
