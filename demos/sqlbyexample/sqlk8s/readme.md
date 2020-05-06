# SQL Server on Kubernetes

In this example, you will learn how to deploy a SQL Server container in Kubernetes. You will also learn how to query the container in Kubernetes, use various commands with the kubectl program to examine the deployment, and finally observe built-in High Availability with Kubernetes, shared storage and a Load Balancer.

## Requirements

All the examples assume a Kubernetes deployment, a bash shell, and an installation of the **kubectl** program. I ran all of my examples in the Azure Cloud Shell against a single node Azure Kubernetes Service (AKS) deployment. These scripts should be generic though and allow you to run this against any k8s deployment. The only caveat is that the scripts assume that k8s supports a Load Balancer service which is typically only for cloud providers like AKS. You could substitute this and use a NodePort for a local k8s deployment.

## Steps

Run each script in "step" order (Example. step1_.., step2_...). To start over, run the cleanup.sh script.

For AKS deployments, you will need to edit **step1_connect_cluster.sh** for your Azure Resource Group and cluster name. The same edits will also need to be done to **step3_setcontext.sh**.

To see a complete tutorial of how to run these scripts look at Module 07 of the SQL Server 2019 Workshop at https://aka.ms/sql2019workshop.

## Notes

You can use an alternate tutorial to this example from the documentation at https://docs.microsoft.com/en-us/sql/linux/tutorial-sql-server-containers-kubernetes?view=sql-server-ver15.