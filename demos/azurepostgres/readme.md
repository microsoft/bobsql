# Demos for Azure PostgreSQL

These are demos for Azure PostgreSQL

## Demo 1 - It’s Postgres

- Show pgadmin
- Show PG deployed in the Azure Portal
- Show psql in the Azure Cloud Shell
- Show psql to load the Shakespeare db and us pgadmin to explore it
- Show pg_stats_activity
- Show how to configure parameters in the Azure Portal
- Show the python app connecting using basic auth. It will fail because the firewall is not configured. Configure this and let the app connect.

## Demo 2 - Building apps with Azure PostgreSQL

- Demo Github Copilot and Intellisense in ADS.
- Show python app with MS Entra authentication
- Show C# app using managed identity

## Demo 3 - AI applications with Azure PostgreSQL

Refer to the demo recording

## Demo 4 - Diving into Performance with Azure PostgreSQL

### pgbench

Show how to run pgbench in the Azure Cloud Shell. Here are the scripts to create the db and populate data

```azurecli
createdb pgbench -h bwpostgres.postgres.database.azure.com -p 5432 -U pgadmin
```

```azurecli
pgbench -i -s 5000 -h  bwpostgres.postgres.database.azure.com -p 5432 -U pgadmin pgbench
```

Use this to run a workload for just SELECT queries

```azurecli
pgbench -T 1200 -c 100 pgbench -h bwpostgres.postgres.database.azure.com -p 5432 -U pgadmin -b select-only
```

### Azure Monitor

Show Azure Monitor in the portal

### Query Store

Show query store queries using pgadmin

Use the gettopqueries.sql and gettopplans.sql scripts to get the top queries and plans

### Query Performance Insight

Show Query Performance Insight in the Azure Portal
