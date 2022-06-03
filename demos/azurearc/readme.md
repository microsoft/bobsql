Here is a good resource to get data controller installed in direct connected mode

https://docs.microsoft.com/en-us/azure/azure-arc/data/create-data-controller-direct-prerequisites?tabs=azure-cli

Create a k8s cluster with AKS and connect it to Azure

1. Deploy AKS
2. Deploy Azure VM with Windows Server 2022 Datacenter (and apply all updates).
3. Install az CLI
4. Run arck8sext.cmd to install az CLI extensions for k8s
5. Login to azure with az login
6. Connect to your AKS cluster using connectaks.cmd
7. Connect your AKS cluster to Azure Arc with connectaksazure.cmd
8. Copy kubectl.exe for Windows to a valid path or local directory
9. Check pods for Azure Arc on k8s are installed with this command: kubectl get pods -n azure-arc. It should look a bit like this


NAME                                        READY   STATUS    RESTARTS   AGE
cluster-metadata-operator-664bc5f4d-ww9jq   2/2     Running   0          2m47s
clusterconnect-agent-7cb8b565c7-bzsf9       3/3     Running   0          2m47s
clusteridentityoperator-5cdbdd8f5f-w7dmv    2/2     Running   0          2m47s
config-agent-84f647998c-j5xf6               2/2     Running   0          2m47s
controller-manager-867fdfdcd6-m26fd         2/2     Running   0          2m47s
extension-manager-57fc477d6f-xfcd4          2/2     Running   0          2m47s
flux-logs-agent-657d46dff4-7c46x            1/1     Running   0          2m47s
kube-aad-proxy-58948b99c9-55hkm             2/2     Running   0          2m47s
metrics-agent-6467bf846b-sfrmh              2/2     Running   0          2m47s
resource-sync-agent-6f64f67dbc-2d8rq        2/2     Running   0          2m47s

Create the data controller

0. Install the arcdata extension for az CLI https://docs.microsoft.com/en-us/azure/azure-arc/data/install-arcdata-extension
1. Create a log analytics workspace
2. Create a direct connected data controller from the Azure Portal per these instructions: https://docs.microsoft.com/en-us/azure/azure-arc/data/create-data-controller-direct-azure-portal.
3. When the azure portal says the DC is ready use this command to see pods that are deployed:  .\kubectl get pods -n azurearcdata. It should look like

NAME                            READY   STATUS    RESTARTS   AGE
bootstrapper-796c4c67db-4jzbf   1/1     Running   0          26m
control-cr5q4                   2/2     Running   0          25m
controldb-0                     2/2     Running   0          25m
logsdb-0                        3/3     Running   0          23m
logsui-x4tmp                    3/3     Running   0          21m
metricsdb-0                     2/2     Running   0          23m
metricsdc-cwf5x                 2/2     Running   0          23m
metricsdc-dq2c5                 2/2     Running   0          23m
metricsdc-vhsfh                 2/2     Running   0          23m
metricsui-46xlx                 2/2     Running   0          23m

Deploy an Azure Arc SQL Managed Instance

You can find instructions here but I like to do this in the portal: https://docs.microsoft.com/en-us/azure/azure-arc/data/create-sql-managed-instance
I would also download SSMS 18 and latest Azure Data Studio build. Install the Azure Arc extension in ADS

1. Create an instance in the portal
2. Follow the status in the portal. When the status is Ready you can check pod status with: .\kubectl get pods -n azurearcdata. This is what mine looked (new pods)` like with an instance name of sqlmia BC service tier

sqlmiaa-0                       4/4     Running   0          3m51s
sqlmiaa-1                       4/4     Running   0          3m51s
sqlmiaa-2                       4/4     Running   0          3m51s
sqlmiaa-ha-0                    2/2     Running   0          5m12s

3. Connect to the instance using the External endpoint listed in the portal using the SQL login you specified in the portal when creating the instance.

Observe Built-in HA

1. Let's enable SQL Server Agent since it is not on by default. Use the script enablesqlagent.cmd. You should expect this to take serveral minutes. If you are using a BC tier it will cause a failover so I like to reset the primary to the original pod. You can use setprimaryreplica.cmd to do this.
2. Create a new SQL Agent job (doesn't matter what is in it. Just a blank job).
3. Create a new blank database using SSMS GUI or CREATE DATABASE
4. Use SSMS to see the AOHA OE options auto show a primary and secondaries and have picked up the new db as having replicas with contained AGs
5. Let's connect to a secondary. To find the secondary endpoint run the command in showarcsqlmi.cmd. This is a big result so search for this


 "secondary": "40.76.148.112,1433"

This is the endpoint to use to connect with SSMS and ADS. This is read-only endpoint

6. Connect to this with SSMS
7. You can see with the Always On Availability Group in OE and see it is a secondary
8. You can see the db you created above
9. You can see the SQL Agent Job is also there which shows you contained AGs.
10. To simulate a failover, run the following command to delete the primary pod (which will get recreated because it is StatefulSet)

.\kubectl delete pod sqlmiaa-0 --namespace azurearcdata

11. Downtime should be in seconds. You can run this command to see the state of all pods

.\kubectl get pods -n azurearcdata

12. You can connect with SSMS for both primary and secondary and see nothing has changed. Except you can see the pod that is now the primary has changed.
13. Run the script setprimaryreplica.cmd to reset the primary. Note that in some cases this did not work (the docs say it is not guaranteed) so I had to delete the new primary pod to get the old primary back as primary.

Management of Azure Arc SQL Managed Instance

1. Connect to Data Controller with ADS
2. Connect to Instance
3. Show Backup history and PITR dialog. Then show dry-run restore example using restoredryrun.cmd

View metrics and logs

1. View metrics in Azure Portal
2. Show Grafana.



