# SQL Server 2022 Demo for Contained Availability Group

These are instructions to setup and demonstrate a contained availability group in SQL Server 2022. This demo will use an Availability Group (AG) without a cluster and no built-in DNS resolution. Therefore there are some manual steps to make this work you would not normally have to do with an AG setup with clustering on Windows. This will require you to perform more manual steps but allows you to setup an contained AG with no Windows Clustering or Windows domain.

## Prereqs

- 2 Virtual Machines running Windows Server each with 4 CPUs and 8Gb RAM
- VMs need to be on the same network and subnet.

**Note**: I used 2 Azure VMs each in the same virtual network. Then I created names in each **C:\windows\system32\drivers\etc\hosts**file for each VM to point to the others private IP address. I used the VM name as the logical name to map to the IP address. This is not required as you can use IP addresses. I found this simpler when using server names in the demo.

- Each VM should have SQL Server 2022 CTP 2.x Evaluation Edition installed. Just install the Database Engine and use all defaults except allow mixed mode security when installing. You can disable the sa login account after installation. You do not need to check the SQL Server Extension to Azure.
- On each VM create firewall rules to allow ports 1433 and 5022
- Enable the Always On Availability Group feature for each SQL instance using the SQL Server Configuration Manager and restart SQL Server.
- Install the latest SSMS 18.x build on each VM.

## Demo Steps

The following are steps to create a contained AG, create a database to be part of the AG, create a SQLAgent Job, and observe the agent job is replicated to the secondary. Then you will execute a manual failover to see how the agent job is now available as part of the new primary.

### Create a contained Availability Group

1. On the primary and secondary VM run the script **sqlsysadminlogin.sql**. This creates a login called sqladmin so we can connect to the difference instances without having to RDP into each one.
1. On the primary and secondary VM start SQL Server agent using SSMS.
1. On the primary VM connect to the primary and secondary instances. Use the local Windows admin if you specified it during setup on the primary or the login from **sqlsysadminlogin.sql**. For the secondary use sqladmin login.
1. Run the script **dbmcreds.sql** for both instances
1. Execute the script **createcert.sql** on the primary
1. Copy the cert files to the secondary instance (you will need to RDP into the second VM)
1. Execute the script **importcert.sql** on the secondary.
1. Execute the script **dbm_endpoint.sql** on both instances
1. On the primary execute the script **createag.sql**
1. On the secondary execute the script **joinag.sql**

You should know have a contained AG. Connect to the primary and use the Always On Availability Group folder in Object Explorer to show the primary and secondary

### Create a database and join it to the AG

1. Connect to the primary instance and run the script **createdb.sql**
1. Connect to the primary instance and run the script **dbjoinag.sql** to join the database to the AG

You can now observe in SSMS that the db is part of the AG but you can also see two databases that are called <agname>_master and <agname>_msdb. These look like user databases but are actually system databases that are part of the replica. They used to sync objects between the two instances.

### See the differences between direct connection and listener

To see the database and instance level replicated objects you need to use a listener. For purposes of this demo we will use another method to simulate a listener. Connect to the instance directly but specify the database name as part of the connection string (in SSMS you can view this with the Options button)

1. Connect to SSMS to the primary instance with the database name you created above.
1. Notice the two "system databases" do not appear in the list of user databases.
1. Create a simple SQL Agent job connected to the listener. The job can be empty. It is just for purposes to see a job object can be replicated.
1. You can now see the SQL Agent job in Object Explorer in SSMS.
1. Connect to the primary instance directly and notice you will not see the job in Object Explore in SSMS. That is because it is stored in the contained system database <agname>_msdb.
1. You can observe the database and agent job on the secondary by connecting directly to the secondary replica instance but using the database name as part of the connection string. This effectively let's you see the contained AG database only and SQL Agent job as replicated.

### Test a failover to see the replicated objects

Since there is no cluster or automatic failover, you can test a manual planned failover using SSMS or T-SQL scripts.

1. Connect directly to the primary instance (no database context in the connection string). 
1. Using SSMS select the Availability Group which is marked as primary, right-click and select Failover
1. Follow the steps in the wizard. Be sure when selecting the secondary to select the right connection login. For my scenario, I used the sqladmin SQL login I created at the beginning of the instructions in the demo.
1. You can now see the secondary is now the new primary and the old primary is the secondary. You can connect to the new primary with the database name context and see the db and SQL Agent job are now part of the new primary.