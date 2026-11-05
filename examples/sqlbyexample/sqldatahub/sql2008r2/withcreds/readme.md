# SQL Server 2008 R2 external source with credentials

A credential-bearing variant of the
[parent SQL Server 2008 R2 example](../readme.md), supplied as
[SQL](sql2008r2_external_table.sql) and a
[notebook](sqlserverexternaltable.ipynb).

Use the parent's SQL Server 2019/PolyBase and remote-database prerequisites.
Run the companion SQL in SQLCMD mode with private `MasterKeyPassword` and
`ExternalSecret` inputs, following
[credential setup](../../../../../SECRET-SCANNING.md#supplying-demo-credentials).
Notebook SQL kernels may not expand those variables. Run setup separately,
then use query cells; saved code outputs have been cleared.

Verify the external query and join behavior on synthetic lab data. Review
notebook outputs before publication, and remove only the lab-owned external
objects using the selected walkthrough's cleanup guidance.
