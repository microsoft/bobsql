# SharePoint data-virtualization example

The [sharepointexternaltable.ipynb](sharepointexternaltable.ipynb) notebook
supports the [SQL Server data-hub walkthrough](../readme.md). It explores
querying SharePoint list data through an external-table scenario.

Read the notebook before execution. Verify the SQL Server/PolyBase version,
Windows/driver requirements, SharePoint access, and private connection settings
for this historical example. Do not assume the notebook's endpoints or
connectors are available in a current environment.

Use synthetic list data and an isolated lab. Review notebook outputs for
credentials and private records before saving or publishing them.
Inspect [cleanup.sql](cleanup.sql) before removing the demo's external objects.
