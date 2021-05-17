# It's Just SQL? demos

Pre-reqs

Deploy a Azure SQL Managed Instance. Use any region but deploy the business critical tier. I used 8 vCores CPUs but any number of CPUs will work

1. Show Azure SQL Managed Instance properties in the portal.
- Show what's in the Overview page. Notice you can create a database in the portal (but you can inside SQL as well)
- Show the vnet and virtual cluster
- Show the Compute+Storage for the various options
- Show the options in Quick Start to get connected
- Show Azure Defender as a service that is part of the value add for the cloud
1. Switch to a VM that is using the public IP and launch SSMS.
1. Notice the different icon and no service capabilities
1. Object Explorer there but a few things missing (like AG)
1. My system databases and user databases all look normal but now run queries in databases.sql to see some different names and file paths.
1. What happens when I try to add a file to a user db and specify a file path (addfile.sql)
1. SELECT @@VERSION is different (version.sql)
1. sp_readerrorlog works from errorlog.sql. Notice a bunch of stuff in there about Azure
1. There is no server configuration manager but none of the options for it are needed. So what about sp_configure? Show various options from sp_configure.sql