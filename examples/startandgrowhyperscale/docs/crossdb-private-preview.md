# Azure SQL Database cross-database queries — private preview
Last updated: **13 October 2026**

Cross-database queries let you use a three-part name to access another database from one Azure SQL Database connection:

```
SELECT ProductId, Quantity
FROM [InventoryDB].[dbo].[Inventory];
```
This is useful for applications that already use `database.schema.object` names in SQL Server. The databases must be online, on the same Azure SQL logical server, and in the same supported elastic pool.

Important

This feature is in private preview. Ask the Azure SQL preview team to enable access and confirm the features available to you. This guide covers Azure SQL Database, not Azure SQL Managed Instance or Microsoft Fabric.

Warning

**A transaction can write to only one database.** It can read several databases and run several write statements, but all writes must be in the same database.

## In this article

- [Supported configurations and limits](#supported-configurations-and-limits)
- [Before you start](#before-you-start)
- [Configure access](#configure-access)
- [SQL examples](#sql-examples)
- [Migration considerations](#migration-considerations)
- [Operations and recovery](#operations-and-recovery)
- [Troubleshooting](#troubleshooting)
- [Remove access](#remove-access)

## Supported configurations and limits
| Area | Current preview |
|---|---|
| Service tiers | **Standard elastic pools and Hyperscale elastic pools** |
| Database location | All participating databases must be online, on the same logical server, and in the same elastic pool. |
| Queries | Three-part names for supported tables, views, functions, and stored procedures. |
| Writes | Supported `INSERT`, `UPDATE`, and `DELETE` statements, with one write database per transaction. |
| Authentication | Microsoft Entra logins, with a user created from the login in every participating database. |
| Permissions | Each database checks its own permissions. Being in the same pool does not grant access. |

More service tiers are planned. Use only the tiers and operations approved for your preview access. Confirm `MERGE`, cross-database DDL, and other statement-specific support with the preview team.

### Transaction limits
The write database can be the database you connected to or another database referenced by a three-part name.

| Within one transaction | Supported? |
|---|---|
| Read several eligible databases and write only to `SalesDB` | Yes |
| Connect to `SalesDB` and update several tables only in `InventoryDB` | Yes |
| Write to both `SalesDB` and `InventoryDB` | No |
| Write to two different remote databases | No |
| Use `SAVE TRANSACTION` or roll back to a savepoint | No |

Count all writes, including those inside stored procedures, triggers, dynamic SQL, and synonyms. For example, an update to `InventoryDB` and an audit write to `SalesDB` are two write databases.

The same rule applies to transactions started by application code. Nested `BEGIN TRANSACTION` statements do not start independent transactions, and an inner `COMMIT` does not end an outer transaction. `BEGIN ... END` groups statements; it does not start or end a transaction.

After a transaction has fully committed or rolled back, a new transaction can write to a different database. **Two separate commits are not one atomic operation**: one can succeed while the other fails.

Check whether your ORM or application framework creates savepoints automatically. Cross-database transactions must use full rollback instead of rollback to a savepoint.

Do not assume a shared snapshot across databases. Confirm the isolation behavior your workload requires with the preview team.

Some preview builds may accept unsupported operations. A statement that runs successfully does not make the operation supported.

### Other limitations

- Cross-database queries cannot access another pool or logical server.
- Four-part names and linked-server behavior are not supported.
- `USE` cannot switch databases on an Azure SQL Database connection. Open a connection to the required database instead.
- Contained users without a server login and cross-tenant Microsoft Entra identities are not supported for this access path.
- Independent database movement or failover while cross-database traffic continues is not supported. See [Operations and recovery](#operations-and-recovery).

## Before you start
You need:

- Private-preview access for your server and pool.
- A Microsoft Entra administrator configured for the logical server.
- A client that supports Microsoft Entra authentication, with network access to the server. Normal firewall and private endpoint requirements still apply.
- A Microsoft Entra identity and the permissions needed in each database.

### Choose an identity
| Identity | When to use it |
|---|---|
| User-assigned or system-assigned managed identity | Application access from an Azure resource that has the identity assigned. |
| Microsoft Entra group | Recommended for managing access for people. |
| Microsoft Entra user | Individual access when a group is not appropriate. |

Confirm service-principal support, including workload identity federation, with the preview team before using it. Do not assume that certificate, client-secret, or SQL authentication is supported just because your tenant or SQL client allows it.

For token-based connections, request an access token for `https://database.windows.net/`. The application connects to the source database and uses three-part names; it does not need a second connection for each target database.

## Configure access
The examples use a managed identity named `contoso-orders-app`. Replace the names and values with your own. A Microsoft Entra administrator runs the setup; the application runs the queries afterward.

These are example objects, not a database installation script. Create or choose suitable test objects before running the grants and queries.

| Database | Object needed by the examples |
|---|---|
| `SalesDB` | `dbo.Orders`, with `OrderId` and `ProductId`; order `1001` refers to a product in `InventoryDB`. |
| `InventoryDB` | `dbo.Inventory`, with a unique `ProductId` and a non-null numeric `Quantity`; the write example uses products `42` and `43`. |
| `InventoryDB` | `dbo.GetInventory`, a read-only stored procedure with an `@ProductId` parameter. Required only for the procedure example. |

**Open a separate connection for each database named in the setup steps.** Do not paste all steps into one connection or add `USE` statements. `GO` separates batches in tools such as SSMS; application code should send the batches separately without `GO`.

### 1. Create the login in master
Connect to `master`, the logical server's virtual master database.

```
CREATE LOGIN [contoso-orders-app]
FROM EXTERNAL PROVIDER;
GO
```
If the name is not unique, follow the [CREATE LOGIN guidance for using an Object ID](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-login-transact-sql?view=azuresqldb-current#d-create-a-login-with-an-alias-using-object-id) before continuing. Use the Microsoft Entra **object ID**, not the application/client ID, and use the resulting login name in the steps below.

### 2. Grant access in SalesDB
Connect directly to `SalesDB`. Create the user from the login and grant read access to the local table.

```
CREATE USER [contoso-orders-app]
FROM LOGIN [contoso-orders-app];
GO

CREATE ROLE [crossdb_reader];
GRANT SELECT ON OBJECT::[dbo].[Orders] TO [crossdb_reader];
ALTER ROLE [crossdb_reader] ADD MEMBER [contoso-orders-app];
GO
```

### 3. Grant access in InventoryDB
Connect directly to `InventoryDB`.

```
CREATE USER [contoso-orders-app]
FROM LOGIN [contoso-orders-app];
GO

CREATE ROLE [crossdb_reader];
GRANT SELECT ON OBJECT::[dbo].[Inventory] TO [crossdb_reader];
ALTER ROLE [crossdb_reader] ADD MEMBER [contoso-orders-app];
GO
```
If the application calls `GetInventory`, also grant `EXECUTE`. Permission to read a table does not grant permission to execute a procedure.

```
CREATE ROLE [crossdb_executor];
GRANT EXECUTE ON OBJECT::[dbo].[GetInventory] TO [crossdb_executor];
ALTER ROLE [crossdb_executor] ADD MEMBER [contoso-orders-app];
GO
```
For the write example, also grant `UPDATE` in `InventoryDB`. Skip this step for a read-only application. Keep the `SELECT` permission above: the update reads columns in its expression and `WHERE` clause.

```
CREATE ROLE [crossdb_inventory_writer];
GRANT UPDATE ON OBJECT::[dbo].[Inventory] TO [crossdb_inventory_writer];
ALTER ROLE [crossdb_inventory_writer] ADD MEMBER [contoso-orders-app];
GO
```
Reuse existing users and roles where appropriate rather than creating them again. Add `INSERT`, `DELETE`, or access to other objects only when needed. Permissions to write in several databases do not allow writing to them together in one transaction.

Do not grant `db_owner` to the application. Do not add `##MS_DatabaseConnector##` unless the preview team confirms it is required. That server role permits connection to every current and future database on the server; it does not grant object permissions.

### Use a user or group instead
Use the same login, mapped-user, and role steps with the person's or group's name instead of `contoso-orders-app`:

| Principal | Example name in the SQL scripts |
|---|---|
| Microsoft Entra group | `[CrossDb-Readers]` |
| Microsoft Entra user | `[user@contoso.com]` |

Assign only the required roles in each database. For a group, create the login and mapped users for the group; members sign in with their own Microsoft Entra identity. Membership changes may require a new token or connection before taking effect.

For example, to add the Microsoft Entra user `sqldba@contoso.com`, connect to `master` and create the server login:

```
CREATE LOGIN [sqldba@contoso.com]
FROM EXTERNAL PROVIDER;
GO
```
Then connect separately to each participating database, create a user mapped to that login, and grant only the required permissions. For `SalesDB`:

```
CREATE USER [sqldba@contoso.com]
FROM LOGIN [sqldba@contoso.com];
GO

GRANT SELECT ON OBJECT::[dbo].[Orders] TO [sqldba@contoso.com];
GO
```
Repeat the mapped-user step in `InventoryDB` and any other database that the user must access. Creating the login in `master` alone does not grant access to the participating databases.

### Check the connection
Connect as the application, user, or group member to `SalesDB`.

```
SELECT
    ORIGINAL_LOGIN() AS login_name,
    USER_NAME() AS database_user,
    DB_NAME() AS connected_database;

SELECT TOP (10) ProductId, Quantity
FROM [InventoryDB].[dbo].[Inventory];
GO
```
Confirm that a read-only identity cannot write, create objects, or add itself to `db_owner`. A successful direct connection to `InventoryDB` alone does not verify the cross-database query from `SalesDB`.

## SQL examples
Run these examples from an application connection to `SalesDB`, using the objects and permissions described in [Configure access](#configure-access).

### Read another database

```
SELECT ProductId, Quantity
FROM [InventoryDB].[dbo].[Inventory]
WHERE ProductId = 42;
```

### Join local and remote tables

```
SELECT o.OrderId, o.ProductId, i.Quantity
FROM [dbo].[Orders] AS o
JOIN [InventoryDB].[dbo].[Inventory] AS i
  ON i.ProductId = o.ProductId
WHERE o.OrderId = 1001;
```

### Call a read-only stored procedure

```
EXEC [InventoryDB].[dbo].[GetInventory]
    @ProductId = 42;
```
For a procedure that writes data, count all of its writes as part of the calling transaction. The procedure cannot add a second write database.

### Run two updates in one database
Use a test database and a fresh connection with no active transaction. Both updates below write to `InventoryDB`. The final `ROLLBACK` undoes both changes, so the example does not commit them.

```
IF @@TRANCOUNT <> 0
BEGIN
    RAISERROR('Use a connection with no active transaction.', 16, 1);
    RETURN;
END;

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE [InventoryDB].[dbo].[Inventory]
    SET Quantity = Quantity + 1
    WHERE ProductId = 42;

    IF @@ROWCOUNT <> 1
        THROW 50001, 'Expected one row for ProductId 42.', 1;

    UPDATE [InventoryDB].[dbo].[Inventory]
    SET Quantity = Quantity + 1
    WHERE ProductId = 43;

    IF @@ROWCOUNT <> 1
        THROW 50002, 'Expected one row for ProductId 43.', 1;

    SELECT ProductId, Quantity
    FROM [InventoryDB].[dbo].[Inventory]
    WHERE ProductId IN (42, 43);

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
```
In application code, use `COMMIT TRANSACTION` when the changes should be saved. Keep all writes in the same database. Adding a write to `SalesDB`, including through a trigger or procedure, is not supported in this transaction.

### Use a synonym
This is optional. As an administrator connected to `SalesDB`, create the synonym and grant access to it:

```
CREATE SYNONYM [dbo].[Inventory]
FOR [InventoryDB].[dbo].[Inventory];

GRANT SELECT ON OBJECT::[dbo].[Inventory] TO [crossdb_reader];
GO
```
The application can then run this query from `SalesDB`. It still needs permission on the target object in `InventoryDB`.

```
SELECT ProductId, Quantity
FROM [dbo].[Inventory]
WHERE ProductId = 42;
```

## Migration considerations
This preview is a good fit for reporting across related databases, reading shared reference data, or writing results into one database. It can reduce changes to existing three-part-name SQL, but it is not the same as moving an entire SQL Server instance unchanged.

| Check before migrating | What to do |
|---|---|
| Database references | Find references in queries, views, functions, procedures, synonyms, and dynamic SQL. Keep names and schema changes coordinated. |
| Transactions | Identify the write database for each transaction, including application-created transactions and writes inside triggers or procedures. |
| Savepoints | Check application code and ORM settings. Use full rollback or choose a supported alternative. |
| Placement | Confirm the actual server and pool resource IDs, not just similar names. Keep the databases together. |
| Permissions | Create the login and mapped users, then grant only the required permissions. Target grants and explicit `DENY` still apply. |
| Collation | String comparisons across databases with different collations may need an explicit `COLLATE` clause. |
| Application libraries | Check your actual driver, connection pool, ORM, and deployment scripts with your workload. |

If a business operation needs atomic writes to several databases, separate commits are not an equivalent replacement. Consider keeping the related data in one database or discuss another supported design with the preview team.

If databases must stay on different servers or move independently, use another supported approach, such as an API or data integration. Teams that share cross-database queries must coordinate schema changes, permissions, and database maintenance.

## Operations and recovery
Keep database placement, login mappings, and permissions in your deployment scripts. Review changes to database names, schemas, collations, identities, network access, and pool membership before applying them.

### Handle errors and interrupted connections

- Roll back the full transaction if it is still active.
- Use connection and command timeouts. Retry only transient errors, with a bounded retry policy.
- Refresh connections and Microsoft Entra tokens when needed.
- After a timeout or lost connection, check whether the write committed before retrying. A lost connection does not prove rollback.
- Use a unique operation ID to avoid applying the same change twice. Store that ID or operation log in the **same database and transaction** as the business changes, not in a separate audit database.

### Plan maintenance, restore, and failover
**Confirm the specific operation with the preview team before relying on it.** The cross-database preview does not itself provide coordinated failover, GeoDR, or a shared recovery point across databases. The one-write-database rule does not establish support for these operations.

For an approved operation, plan for all databases the application depends on. Pause dependent traffic as required; do not keep issuing cross-database queries while databases are split across servers or pools.

Before resuming traffic:

1. Confirm that every database is online on the intended server and in the same supported pool.
2. Check names, login mappings, users, permissions, and network access. Repeat these checks after restore, copy, or recreation.
3. Run direct database checks and cross-database queries. Check both new and reused application connections.
4. Reconcile interrupted business operations before resuming writes. Restored databases or databases recovered after a forced failover may reflect different points in time.
Apply the same checks after an approved failback. Passing these checks does not turn an unapproved failover or GeoDR scenario into a supported one.

## Troubleshooting
| Error or symptom | What to check |
|---|---|
| `18456`: login failed | Microsoft Entra tenant, token audience and expiry, server administrator, login name, and object ID. |
| `916`: cannot access the target database | Login, target user created from that login, and permissions. Try direct source and target connections, then the cross-database query. |
| `229`: permission denied | Target grants, role membership, and explicit `DENY`. |
| `208`: invalid object name | Database, schema, and object names; online state; permissions; and whether both databases are in the same server and pool. |
| `40508`: `USE` is not supported | Open a connection to the required database instead. |
| `40515`: unsupported database or server reference | Check the same-server and same-pool requirements. |
| `46971`: a transaction cannot write to multiple databases in an elastic pool | Keep all writes in one database. Roll back the full transaction if it is still active. |
| The application uses a savepoint | Remove the cross-database dependency on `SAVE TRANSACTION` and rollback to a savepoint. Use full rollback instead. |

If direct connections work but the cross-database query fails with `916`, capture the failing query and contact the preview team. Do not work around it by granting `db_owner` or a broad server role.

### Error 46971: writes to multiple databases
Example output:

```
Msg 46971, Level 16, State 1, Line 371
A transaction cannot write to multiple databases in an elastic pool.
```
The transaction attempted to write to a second database. Check indirect writes as well as the statements in the batch. Reads across eligible databases and several writes in one database remain allowed.

Roll back the full transaction if it is still active, then change the operation to use one write database. **Do not retry the same multi-database write transaction unchanged.** Splitting it into separate commits changes the all-or-nothing behavior.

`Line 371` is specific to this example. The error does not guarantee a particular `XACT_STATE()` or prove that the full transaction was rolled back. Not receiving `46971` does not make multi-database writes supported. Savepoints are a separate limitation; this is not a savepoint error.

### Capture diagnostics
Ask a database administrator to check the source and target databases:

| What to inspect | Examples |
|---|---|
| Requests and sessions | `sys.dm_exec_requests`, `sys.dm_exec_sessions` |
| Waits and locks | `sys.dm_os_waiting_tasks`, `sys.dm_tran_locks` |
| SQL text and plans | `sys.dm_exec_sql_text`, `sys.dm_exec_input_buffer`, `sys.dm_exec_query_plan` |
| Transactions | `sys.dm_tran_session_transactions`, `sys.dm_tran_active_transactions`, `sys.dm_tran_database_transactions` |

Live DMV information is temporary. Use Query Store or configured Extended Events to investigate completed requests. Diagnostic access requires its own permissions; do not grant the application administrator rights to collect it. SQL text, plans, and captured values can contain sensitive data.

## Remove access
Run these steps as an administrator, not as the application. Stop the application connections first. Remove mapped users from every database where they were created before dropping the server login.

Connect to `SalesDB`:

```
ALTER ROLE [crossdb_reader] DROP MEMBER [contoso-orders-app];
DROP USER [contoso-orders-app];
GO
```
Connect to `InventoryDB`. Run the optional role-removal statements only for memberships you assigned:

```
ALTER ROLE [crossdb_reader] DROP MEMBER [contoso-orders-app];
-- If assigned:
-- ALTER ROLE [crossdb_executor] DROP MEMBER [contoso-orders-app];
-- ALTER ROLE [crossdb_inventory_writer] DROP MEMBER [contoso-orders-app];
DROP USER [contoso-orders-app];
GO
```
Finally, connect to `master`:

```
DROP LOGIN [contoso-orders-app];
GO
```
Keep shared roles and the application tables. For a user or group, replace the principal name in these statements with the name you configured.

Azure SQL Database cross-database queries — private preview