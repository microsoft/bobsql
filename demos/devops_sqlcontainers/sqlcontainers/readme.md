# Demo for fundamentals of using SQL Server containers

Steps to show a demonstrations of the fundamentals of using SQL Server Containers

## Setup

- Internet connection
- Install Docker for Desktop on Mac, Linux, or Windows

## Run a SQL Server container

Use one of the following scripts depending if you are a Windows or Mac/Linux user

**Windows Users**

Run the following script from a Powershell command prompt:

`runsqlcontainer.ps1`

**Mac/Linux users**

Run the following script from a bash shell prompt:

`runsqlcontainer.sh`

If the container image does not exist locally docker will first pull the image locally and then run the container. The scripts are setup to "just work" so when the container starts you will be put back at the command prompt

## Connect to the container and run a query

1. Connect to SQL Server using the connection string `localhost,1401`

Use the login **sa** and password **Sql2022isfast**

2. Execute the following query

```sql
SELECT @@VERSION
```

You should get back results for Developer Edition and the latest SQL Server 2022 relaase (depending on what Cumulative Update has been released).

3. Show XEProfiler
1. Create a new database

## See what containers are running

1. Show `docker ps` from the Terminal in VS Code
1. Show `docker images` from the Terminal in VS Code
1. Show the docker Windows app. Click on the image and show the properties.
1. Show **execincontainers.ps1** to show how to look "inside" the container including running sqlcmd.
1. Show **containerlogs.ps1** so you can see the ERRORLOG outside the container.

## How to customize a SQL Server container

1. Examine the **docker-compose.yml** and files in the **bwsql** directory.

2. Execute the following command:

`docker-compose up`

3. In the command window you will see information about the container starting up and then messages about objects being created in the database.

4. Connect with SSMS to the container with **localhost,1402** to see the db, objects, and data.