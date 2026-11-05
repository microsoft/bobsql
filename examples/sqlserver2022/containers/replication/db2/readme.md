# Replication container: db2

Companion container assets for the [replication walkthrough](../README.md):
[Dockerfile](Dockerfile), [entrypoint.sh](entrypoint.sh),
[db-init.sh](db-init.sh), and [db-init.sql](db-init.sql).

Run through the parent orchestration with [db1](../db1/readme.md), not as an
independent database tutorial. Inspect SQL initialization, connection targets,
startup ordering, and private authentication configuration before execution.
Supply the private runtime password as described in the parent walkthrough.

Verify the replication scenario using the parent instructions and remove
containers/volumes only after confirming the cleanup scope.
