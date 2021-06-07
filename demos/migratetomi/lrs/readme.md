# Online migration using Log Replay Service (LRS)

Review the following requirements at https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/log-replay-service-migrate#requirements-for-getting-started. This includes specific versions of Powershell Azure modules..

For this example, we will use a single Azure storage account to directly backup the dbs to Azure Storage from a VM and then use LRS to restore from the same storage container.

1. Deploy SQL Server 2016 in Azure VM or use an existing instance in Azure VM.

2. Create a single database with baylorbearsnationalchamps.sql

3. Create an Azure Storage account per the guidance at https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/log-replay-service-migrate#requirements-for-getting-started

- Skip the section "Make backups of SQL Server"
- Follow the steps in the section "Create a storage account"
- Generate a SAS token per the instructions https://docs.microsoft.com/en-us/sql/relational-databases/tutorial-use-azure-blob-storage-service-with-sql-server-2016?view=sql-server-ver15#1---create-stored-access-policy-and-shared-access-storage.

4. Modify cred.sql to use the new SAS token and execute cred.sql

5. 