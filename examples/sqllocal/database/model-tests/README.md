# Isolated chat and embedding tests from T-SQL

Call the existing authenticated Azure Local gateway through
`sys.sp_invoke_external_rest_endpoint`, independently of the application's
briefing workflow. These scripts use `CaldovaFoundryModelTests`, not the
application database, and do not persist a receiving briefing.

## Configure and initialize

First complete [gateway/trust setup](../../setup/README.md), enable server
configuration `external rest endpoint enabled`, and replace the reserved
example IP `192.0.2.10` consistently in both SQL tests and
[Initialize-FoundrySqlTests.ps1](../../setup/Initialize-FoundrySqlTests.ps1).
Credential names must match the endpoint prefixes.

From the collection root, using Windows integrated SQL administrator access:

```powershell
.\setup\Initialize-FoundrySqlTests.ps1 `
    -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig'
```

This creates the dedicated user database if absent, enables
`PREVIEW_FEATURES` there, creates a master key if missing, and creates or
refreshes two encrypted database-scoped credentials from Kubernetes secrets.
No key is printed or stored in these SQL files. Credentials persist across
SQL restarts; rerun initialization after key rotation. Do not use
`-ApplicationVectorSearch` for these isolated tests: that switch targets the
application database instead.

## Run in VS Code MSSQL or SSMS

Connect to your SQL Server and execute the chosen script:

| Script | Expected successful result |
| --- | --- |
| [test-chat.sql](test-chat.sql) | HTTP 200, return code 0, nonempty reply from `gpt-oss-20b` |
| [test-embeddings.sql](test-embeddings.sql) | HTTP 200, return code 0, all 2,048 finite numeric embedding dimensions from `nemotron-3-embed-1b-bf16` |

Change the synthetic `@Prompt` / `@Input` to try another example.
`@ShowFullResponse = 1` exposes full output; failures report the response and
throw. Do not share response logs containing private prompts or environment
details.

The embedding test validates the REST JSON then converts it to
`VECTOR(2048, float16)` without discarding dimensions. Standard float32
vectors support only 1,998 dimensions; half precision reduces numeric
precision and requires preview support in a user database. This is why the
test does not use `tempdb`. `AI_GENERATE_EMBEDDINGS` is not used by these
diagnostic scripts.

Results and timings are measurements of your configured environment, not
performance guarantees. Initialization does not prove live inference; require
the successful SQL result and validation from each test.

## References and cleanup

- [REST endpoint procedure](https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql?view=sql-server-ver17)
- [Vector type](https://learn.microsoft.com/sql/t-sql/data-types/vector-data-type?view=sql-server-ver17)
- [Half-precision vectors](https://learn.microsoft.com/sql/t-sql/data-types/vector-data-type-half-precision-float?view=sql-server-ver17)

Remove the dedicated test database only when it is no longer needed and you
have confirmed it contains no data you need. Do not delete the application
database or shared Kubernetes secrets as test cleanup.
