# Build the ZavaHospital database

Database setup scripts for the [hospital walkthrough](../readme.md). Complete
[NIM setup](../nvidianim/README.md) first, then follow the parent's numbered
setup sequence from [01_schema.sql](01_schema.sql) through the embedding,
vector-index, and doctor-note search scripts.

Inspect database names, SQLCMD placeholders, endpoint names, model dimensions,
and authentication before execution. Supply secrets privately as described in
the parent configuration table. Seed scripts create synthetic demonstration
data and modify the target database.

Run the parent's validation queries after each stage. Optional scripts such as
`zavaces.sql` have their own Azure dependencies; do not execute every file
indiscriminately. Once setup is verified, use the [presentation scripts](../demo/readme.md).
