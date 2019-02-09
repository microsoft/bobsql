# SQL Containers demo showing volume storage and update/upgrade of containers

**Note:** This demo assumes you have completed the steps in the sqlcontainers exercise and left the containers running from that exercise.

1. Let's update the sql2017cu10 container with the latest CU by running **step1_dockerupdate.sh**. This has to run a few upgrade scripts so takes a few minutes. While this is running, let's look at volume storage.

2. See details of the volumes used by the containers from the sqlcontainers exercise volumes by running **step2_inspectvols.sh**.

3. See what files are stored in the host folders used to provide volume storage by running **step3_volstorage.sh**.

