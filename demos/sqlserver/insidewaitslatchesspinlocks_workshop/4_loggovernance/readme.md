# Debugging LOG_RATE_GOVERNOR waits

1. Deploy 2 Azure SQL Databases: GP 8 Vcore AND BC 8 Vcore

2. Run ddl.sql for both dbs to create the database

3. Run filltable.sql for both dbs to populate data into the table

4. Load loggovernance.sql for the context of the GP db and loggovernancebc.sql for the context of the BC db

5. Load selinto.sql for the context of the GP db and selintobc.sql into the context for the BC db

6. Run selinto.sql and observe each query in loggovernance.sql

7. Do the same for selintobc.sql and loggovernancebc.sql

