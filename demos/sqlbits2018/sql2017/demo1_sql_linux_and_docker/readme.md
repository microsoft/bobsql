This demo shows how to explore SQL Server on Linux. It assumes you have already installed SQL Server on Linux. This demo uses Red Hat Linux Enterprise 7.4 but you can use these steps on other Linux Distributions.

To learn more about installing SQL Server on Linux go to https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup.

For this demo, I use the following tools and files:

- ssh client: I'm a Windows user so my preferred ssh client is MobaXterm which you can install from https://mobaxterm.mobatek.net
- Docker Engine for Windows - Install this at https://docs.docker.com/docker-for-windows. My demos assume docker for powershell syntax but all of these will work on any Docker Engine making the necessary changes for the bash shell syntax on Mac or Linux. I recommend you configure the Docker Engine on Windows to have at least 4096Mb of memory.

1. Now that SQL Server is installed and running, let's explore a bit.

sudo systemctl status mssql-server

Notice the 2 sqlservr processes. The top one is the parent "watchdog" process

ps axjf | grep sqlservr - Shows the parent process tree

2. Where are the files?

sudo tree /opt/mssql | more
sudo tree /var/opt/mssql | more

3. What about the ERRORLOG?

sudo cat /var/opt/mssql/log/errorlog
sudo tail /var/opt/mssql/log/errorlog

4. The mssql-conf script

sudo /opt/mssql/bin/mssql-conf
sudo /opt/mssql/bin/mssql-conf list

5. Quick commands to monitor

sudo top
sudo iotop
sudo htop
sudo sar

6. Let's now look at docker

Examine and run dockerpull.cmd to pull down the latest docker SQL Server 2017 image.

7. See what images are pulled down to your environment

docker image

8. Start a container

Examine and run dockerrun.cmd to start a container

9. See what containers are running

docker ps

10. Interact with the container using bash

Examine and run dockerbash.cmd

11. Connect to the server using sqlcmd installed inside the container

/opt/mssql-tools/bin/sqlcmd -Usa -PSql2017isfast

And run

select @@version

12. Interact with SQL Server outside the container

sqlcmd -S127.0.0,1,1401 -Usa

and run

select @@version
