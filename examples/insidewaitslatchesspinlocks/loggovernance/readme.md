# Transaction-log governance

Workload and diagnostic scripts for observing log-rate governance. Start by
reading [ddl.sql](ddl.sql), [loggovernance.sql](loggovernance.sql),
[loggovernancebc.sql](loggovernancebc.sql), and
[dmexecrequests.sql](dmexecrequests.sql) to select the database/tier scenario.

Use a disposable target and the SQL client/workload tools referenced by the
command files. Review server names, database names, file paths, and resource
limits before generating load. Fill-table, SELECT INTO, and bulk-insert scripts
write data and can consume significant log throughput and storage.

[BulkInsert.sql](BulkInsert.sql) includes inherited credential examples; supply
private configuration rather than reusing or publishing literal values.
Treat bundled backup files as lab artifacts requiring independent review.
Stop drivers and inspect [cleanup.sql](cleanup.sql) before removing lab objects.
