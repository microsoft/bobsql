These are files to demonstrate SQL Server with Docker Containers. Files are provided to use with Docker for Windows and Docker for MacOS

Whether you are a Windows or MacOS user, you should download the WideWorldImporters sample database backup from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak

Windows Users

All of the following scripts can be run in Powershell or a Windows command prompt

1. Install Docker for Windows from https://www.docker.com/docker-windows

Install SQL Server utilities for Windows which includes sqlcmd.exe from https://www.microsoft.com/en-us/download/details.aspx?id=53591

2. Pull the latest SQL Server Docker Image by executing dockerpull.cmd. This requires your computer be connected to the internet

3. Edit the dockerrun.cmd file to specify your preferred sa password.

4. Run the container by executing dockerrun.cmd script

5. Verify the container is running by executing this command

docker ps

The output should look something like this

CONTAINER ID        IMAGE                                      COMMAND                  CREATED             STATUS              PORTS                    NAMES

07d24d9ac18c        microsoft/mssql-server-linux:2017-latest   "/opt/mssql/bin/sqls…"   2 seconds ago       Up 1 second         0.0.0.0:1401->1433/tcp   sql1

6. Interact with the container through a bash shell by executing dockerbash.cmd

You will be prompted with a bash shell prompt

Dump out the errorlog with cat by typing in this command

cat /var/opt/mssql/log/errorlog

Exit the bash shell by typing in exit at the bash shell prompt

7. Let's restore the WideWorldImporters sample database into the container

Move or copy the WideWorldImporters sample backup to your local directory

Execute the dockercopy.cmd script to copy the backup into the container

Restore the backup by executing the docker_restorewwi.cmd

8. Query a table in the WideWorldImporters database

Execute the dockerquery.cmd script to connect to the container and run a query to the database. You will be prompted for your sa password

9. Stop the container by executing dockerstop.cmd

10. Remove the container by execute dockerremove.cmd

11. See that the volume is still there (which includes the WideWorldImporters database) even though the container is removed by executing dockervolume.cmd

12. Start a new container using the same volume to show another container can use the persisted database

Execute dockerrun2.cmd

Execute dockerquery.cmd to connect and query a table in the database

13. To clean up demo to run again, follow these steps

Execute dockerstop2.cmd

Execute dockerremove2.cmd

Execute dockervolumeremove.cmd

docker images

docker rmi <IMAGE ID>

MacOS Users

All of the following scripts can be run in macOS terminal. After copying all the .sh files into our directory execute this command from the terminal

chmod u+x docker*.sh

1. Install Docker for MacOS from https://docs.docker.com/docker-for-mac/install/

Install SQL Command Utilities for macOS from https://blogs.technet.microsoft.com/dataplatforminsider/2017/05/16/sql-server-command-line-tools-for-macos-released/

2. Pull the latest SQL Server Docker Image by executing dockerpull.sh. This requires your computer be connected to the internet

3. Edit the dockerrun.sh file to specify your preferred sa password.

4. Run the container by executing dockerrun.sh script

5. Verify the container is running by executing this command

docker ps

The output should look something like this

CONTAINER ID        IMAGE                                      COMMAND                  CREATED             STATUS              PORTS                    NAMES

07d24d9ac18c        microsoft/mssql-server-linux:2017-latest   "/opt/mssql/bin/sqls…"   2 seconds ago       Up 1 second         0.0.0.0:1401->1433/tcp   sql1

6. Interact with the container through a bash shell by executing dockerbash.sh

You will be prompted with a bash shell prompt

Dump out the errorlog with cat by typing in this command

cat /var/opt/mssql/log/errorlog

Exit the bash shell by typing in exit at the bash shell prompt

7. Let's restore the WideWorldImporters sample database into the container

Move or copy the WideWorldImporters sample backup to your local directory

Execute the dockercopy.sh script to copy the backup into the container

Restore the backup by executing the docker_restorewwi.sh

8. Query a table in the WideWorldImporters database

Execute the dockerquery.sh script to connect to the container and run a query to the database. You will be prompted for your sa password

9. Stop the container by executing dockerstop.sh

10. Remove the container by execute dockerremove.sh

11. See that the volume is still there (which includes the WideWorldImporters database) even though the container is removed by executing dockervolume.sh

12. Start a new container using the same volume to show another container can use the persisted database

Execute dockerrun2.sh

Execute dockerquery.sh to connect and query a table in the database

13. To clean up demo to run again, follow these steps

Execute dockerstop2.sh

Execute dockerremove2.sh

Execute dockervolumeremove.sh

docker images

docker rmi <IMAGE ID>