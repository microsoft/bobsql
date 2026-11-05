This demo shows you how to setup a clusterless cross-platform AG between a Windows Server and Linux. This is basically a similar set of steps as documented at https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-availability-group-cross-platform

This demo requires:

- SQL Server 2017 for Windows. for my demo, I install SQL Server 2017 in a VM on Windows Server 2016
- SQL Server 2017 for Linux. For my demo, I install SQL Server on Linux in a VM running RHEL 7.4
- SQL Server Management Studio. You can download this from https://docs.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms
- The WideWorldImporters sample database. You can download this from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak

1. Install SQL Server 2017 on Windows Server 2016 and enable Availability Groups from SQL Server Configuration Manager

2. Install SQL Server 2017 on Linux. Enable HADR via mssql-conf like this

sudo /opt/mssql/bin/mssql-conf set hadr.hadrenabled 1

3. Open up firewall ports for TPC 1433 and 5022 on both Windows and Linux. Configure hosts on both servers or register with DNS. For my demo, my Windows Server is using a VM with WS2016 and is registered with a fixed IP address in my hosts file on my host laptop as bwsq2017ws2016. My linux VM is registered on my hosts file on my laptop host as bwsql2017rhel. For Windows the hosts file can be found in c:\windows\system32\drivers\etc.

4. On the Windows server, run the primary_setup_login.sql script to create the login and user on the primary

5. On the Windows Server, run the primary_setup_key.sql script to create a master key and certificate on the primary

6. Copy the .cer and .pvk file created from Step 6 into the /var/opt/mssql/data directory on the Linux server. Run these commands to change ownership of these files

sudo chown mssql:mssql /var/opt/mssql/data/dbm_certificate.pvk
sudo chown mssql:mssql /var/opt/mssql/data/dbm_certificate.cer

FYI. I install a slick program called winscp on my windows laptop to copy files between my Windows machine and Linux server. Programs like Mobaxterm also provide some nice drag and drop copy capabilities

7. Connect to the Linux server and run secondary_setup_login.sql to create the login and user.

8. Run secondary_setup_key.sql to create the master key and restore certificate from the files you copied from the Windows Server.

9. Run primary_setup_endpoint.sql to setup a dbm endpoint on the primary Windows Server

10. Run secondary_setup_endpoint.sql to setup a dbm endpoint on the secondary Linux Server.

11. On the primary Windows Server run the primary_create_ag.sql. Modify the replica names and the ENDPOINT_URL to match your hostnames.

12. On the primary Windows Server run primary_add_db_to_ag.sql to create a db and add it to the AG.

13. On the secondar Linux Server run secondary_join_ag.sql to join to the AG.

14. Now observe im SSMS that the database is there on the secondary replica