This demo shows how to deploy and explore SQL Server on Linux. To learn more about installing SQL Server on Linux go to https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup.

For this demo, I use the following tools and files:

- ssh client: I'm a Windows user so my preferred ssh client is MobaXterm which you can install from https://mobaxterm.mobatek.net
- I'll be installing SQL Server on a RHEL 7.4 VM on my Windows 10 laptop using a Hyper-V VM.

1. Let's deploy SQL Server on Linux

Download the repo file for RHEL

sudo curl -o /etc/yum.repos.d/mssql-server.repo https://packages.microsoft.com/config/rhel/7/mssql-server-2017.repo

2. Install SQL Server

sudo yum install -y mssql-server

3. Run mssql-conf to complete the install

sudo /opt/mssql/bin/mssql-conf setup

4. Now that SQL Server is installed and running, let's explore a bit.

sudo systemctl status mssql-server

Notice the 2 sqlservr processes. The top one is the parent "watchdog" process

ps axjf | grep sqlservr - Shows the parent process tree

5. Where are the files?

sudo tree /opt/mssql | more
sudo tree /var/opt/mssql | more

6. What about the ERRORLOG?

sudo cat /var/opt/mssql/log/errorlog
sudo tail /var/opt/mssql/log/errorlog

7. The mssql-conf script

sudo /opt/mssql/bin/mssql-conf
sudo /opt/mssql/bin/mssql-conf list

8. Quick commands to monitor

sudo top
sudo iotop
sudo htop
sudo sar

9. Restore a db and connect to it

I have a script called cpwwi.sh that is provided for you I use inside my VM to copy the WideWorldImporters-Full.bak to /var/opt/mssql
I also have a script called restorewwi.sh which uses sqlcmd to call restorewwi_linux.sql to restore the WWI backup

10. Use mssql-cli on Linux now to interact with it

mssql-cli -Usa

Use intellisense to change context to WWI and select from Sales.SpecialDeals

Notice the output in a vertical "node" format vs the traditional row format that may wrap around on your screen (you can configure this)

11. Let's try something a bit advanced and fun. Let's kill SQL Server and see what happens

sudo systemctl status mssql-server

The <pid> is the 2nd sqlservr process

sudo kill -s SIGSEGV <pid>

Now run sudo systemctl status mssql-server to observe processes to capture core dump and new sqlservr processes being generated

Now let's really kill it

sudo kill -s SIGKILL <pid>

Be sure to use the new 2nd PID after the first kill.

