1. Run dockerruncu8.sh to start a container with SQL Server 2017 CU8. This container is called sql1

2. Run dockercopy.sh and docker_restorewwi.sh to restore the WWI into the sql1 container.

3. Run dockerrun2.sh to start another SQL container with the latest SQL 2017 update. This container is called sql2

4. Run ps -axf to see all the SQL Server child proceses under the docker daemon. Note the process IDs of the sqlservr processes

5. Run sudo lsns to see the namespaces for these containers

6. Run cat /proc/meminfo and lscpu to see the memory and CPUs for this machine

7. Now let's dive into one of the containers by running

sudo docker exec -it sql1 bash

8. Run ps -axf to see the list of processes. Note how few procs are there and how sqlservr has different PIDs

9. Run cat /proc/meminfo and lscppu to see memory and CPUs within the container. By default each container has access to all memory and CPUs.

10. Type 'exit' to leave the container

11. How do we know sql2 can't see the WWI db we restore. Let's look at the volumes

sudo docker volume ls

12. Run these commands to find out where the host storage is for the volume

sudo docker inspect sqlvolume sqlvolume2

13. List out the contents of each Mountpoint with something like

sudo ls -l /var/lib/docker/volumes/sqlvolume/_data/data
sudo ls -l /var/lib/docker/volumes/sqlvolume2/_data/data

Notice the WWI database is only in sqlvolume and not sqlvolume2

14. Optional: If you have SQL Server already installed try this

sudo systemctl stop mssql-server
sudo /opt/mssql/bin/sqlservr --help

Notice the following parameter in the output

Administrative options:
  --accept-eula             Accept the SQL Server EULA
  --pid <pid>               Set server product key
  --reset-sa-password       Reset system administrator password. Password should
                            be specified in the MSSQL_SA_PASSWORD environment
                            variable.

So this is how SQL Server starts and sets EULA, PID, and sa password since mssql-conf is not run
