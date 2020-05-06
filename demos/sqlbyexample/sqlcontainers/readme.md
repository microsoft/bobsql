# SQL Server Containers

In this example, you will learn how to deploy a SQL Server container. 

## Requirements

All the examples use Docker Desktop which you can install at https://www.docker.com/products/docker-desktop. These examples require an internet connection as images will be pulled to your machine. If you prefer to run these examples on Linux with the bash shell see the SQL Server 2019 workshop at https://aka.ms/sql2019workshop.

You will also need to download the WideWorldImporters sample backup (which you can download from https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak) and copy it into the c:\sql_sample_databases directory or modify step2_copyintocontainer.ps1 to put in the proper path for the backup.

## Steps

Run each script in "step" order (Example. step1_.., step2_...). To start over, run the cleanup.ps1 script.

To see a complete tutorial of how to run these scripts look Module 06 of the SQL Server 2019 Workshop at https://aka.ms/sql2019workshop.

## Notes

To get a complete list of SQL Server containers for Ubuntu use the Docker Hub page at https://hub.docker.com/_/microsoft-mssql-server.  A complete list of SQL Server containers for RHEL can be found at https://catalog.redhat.com/software/containers/explore.

Tip: To "hack" into the Docker Desktop Virtual Machine on Windows, run a container like the following:

`docker run --net=host --ipc=host --uts=host --pid=host -it --security-opt=seccomp=unconfined --privileged --rm -v /:/host alpine /bin/sh`
