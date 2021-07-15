# Monitoring and Availability demos

Pre-reqs

Deploy a Azure SQL Managed Instance. Use any region but deploy the business critical tier. I used 8 vCores but any number of CPUs will work

1. Do my DMVs work?

    Check out the DMVs that are common to SQL Server and unique to Azure SQL Managed Instance in sqlmidmvs.ipynb.

2. What about XEvents?

- Use SSMS to see the system_health session
- Look at XEvent SQL Profiler with a live trace. You can see the types of activities from services related to PaaS in this trace.

3. Monitoring outside of SQL

    Show the new SQL Insights Preview in the portal.

4. How about backup and restore?

- Use the portal to show available PITR and retention options
- Show deleted databases
- Use the XEvent trace to see backup history

5. What about HA?

- Show some of the queries in hadr_fabric.sql
- Show a SQLAgent job (I created a simple T-SQL one step job)
- Use ostress to run connect.ps1
- Run failover.ps1
- See the ostress session get errors and then connect again (retries)
- After reconnecting show the job still exists.