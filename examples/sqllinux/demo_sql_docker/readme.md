This demo is to show the capabilities of SQL Server and Docker

For this demo, I use the following tools and files:

- Docker Engine for Windows -  Install this at https://docs.docker.com/docker-for-windows. My demos assume docker for powershell syntax but all of these will work on any Docker Engine making the necessary changes for the bash shell syntax on Mac or Linux. I recommend you configure the Docker Engine on Windows to have at least 4096Mb of memory.
- SQL Operations Studio - Download from https://docs.microsoft.com/en-us/sql/sql-operations-studio/download
- mssql-cli - Download from https://github.com/dbcli/mssql-cli/blob/master/doc/installation_guide.md

1. Examine and run dockerpull.cmd to pull down the latest docker SQL Server 2017 image.

2. See what images are pulled down to your environment

docker image

3. Start a container

Examine and run dockerrun.cmd to start a container

4. See what containers are running

docker ps

5. Let's copy the WWI backup into the container and restore it

Examine, modify if necessary the path to the backup file, and run dockercopy.cmd

6. Restore the database backup

Examine and run docker_restorewwi.cmd which executes sqlcmd inside the container to restore the WWI db.

7. Let's interact with the container in SQL Ops Studio

Use SQL Ops Studio to connect to 127.0.0.1,1401

8. Expand the db tree to see WideWorldImporters db

9. Open up the Integrated Terminal in Ops Studio under the View Menu. We are now interacting with the local Windows (or whatever local OS you ran Ops Studio on) host

10. Stop the container by running this command in that terminal window

docker stop sql1

You will see Ops Studio can't interact anymore with that connection because SQL Server is stopped

11. Start the container again

docker start sql1

Notice that the WideWorldImporters database is still there. This is becasue we only stopped and started the container. If we remove the container then the restored db would be lost unless we use persisted storage

12. Interact with the container in the terminal with mssql-cli

mssql-cli -h127.0.0.1,1401 -Usa

So now I'm running SQL Ops Studio using their Integrated Terminal running mssql-cli to connect to my Docker Container running SQL Server on Linux. Try to digest that for a few mins

BONUS:

If you have a Linux server avaialble that your machine where you are using Ops Studio can connect to, use the Integrated Terminal to do this

ssh <user>@<linux server>

mssql-cli -Usa

Now you are using the Integrated Terminal in Ops Studio to run mssql-cli remotely on the Linux Server
