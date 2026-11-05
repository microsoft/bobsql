# Replication container: db1

Container build and initialization assets for the
[replication walkthrough](../README.md):
[Dockerfile](Dockerfile), [entrypoint.sh](entrypoint.sh),
[db-init.sh](db-init.sh), and [db-init.sql](db-init.sql).

Use the parent orchestration rather than launching initialization scripts
independently. Review database roles, connectivity, startup ordering, and
credentials alongside the companion [db2](../db2/readme.md) container.
Supply the private runtime password as described in the parent walkthrough;
the publisher derives SQL-escaped replication credentials from that input.

Use a disposable Docker lab and the parent's verification and cleanup steps.
