## Setup for the Azure Arc-enabled SQL Managed Instance demo

The following are setup steps required for the Azure Arc-enabled SQL Managed Instance demo. These are the required steps in order to prepare to deploy an Azure Arc-enabled SQL Managed Instance which will be covered in the **deploy_and_migrate** steps.

Here is an outline of the steps you will perform to setup the demo:

- Install the necessary tools in your client machine.
- Register the Microsoft.AzureArcData provider in Azure.
- Create and/or connect to a Kubernetes Cluster. This demonstration uses an Azure Kubernetes Cluster (AKS) deployed in Azure.
- Create an Azure Arc data controller

You can follow along these steps from this documentation page: <https://learn.microsoft.com/azure/azure-arc/data/create-data-controller-direct-prerequisites>

## Install tools

Install the following tools in your client machine or VM per this documentation page: <https://learn.microsoft.com/azure/azure-arc/data/install-client-tools>

> **Note:** For purposes of this example I created a client VM using Azure Virtual Machine with Windows Server 2022.

- az CLI
- arcdata extension for Azure (az) CLI
- Azure Data Studio
- Azure Arc extension for Azure Data Studio
- kubectl
- SQL Server Management Studio 19 (latest version)

## Register the Microsoft.AzureArcData provider

Run the following az CLI command

```azurecli
az provider register --namespace Microsoft.AzureArcData
```
## Create and/or connect to the k8s cluster

1. Create a K8s cluster. For purposes of this exercise I created a cluster with AKS in Azure.
2. Connect to the AKS cluster using the following az CLI command from the client machine. 

```azurecli
az aks get-credentials --resource-group <resource_group_name> --name <cluster_name>
```
You can find this command also in the provided script **getakscreds.cmd**.

3. Arc enable the AKS cluster using the following command:

```azurecli
az connectedk8s connect --resource-group <resource group> --name <cluster name>
```
You can find this command in the following script **connectakstoazure.cmd**.

4. Verify in the Azure portal the cluster shows up as a Kubernetes Azure Arc resource.

## Create an Azure Arc data controller

You will now deploy the Azure Arc data controller on the Azure Arc-enabled k8s cluster in direct mode. Follow the steps as outlined in the following documentation <https://learn.microsoft.com/azure/azure-arc/data/create-complete-managed-instance-directly-connected#create-the-data-controller>

1. Create a log analytics workspace used for uploading logs. Use the Agents on the left hand menu to get a workspace id and key to use when deploying the data controller.

1. Create the data controller in the Azure portal per the instructions in the documentation. You will create a new custom location as part of this step. You will need the name of the data controller and custom location when deploying the Azure Arc-enabled SQL Managed Instance.

1. The Azure Portal will show the deployment as complete but if you look at the status of the Azure Arc data controller in the portal it will show a status of *Deploying*. The full deployment will take several minutes. When complete the portal should show a status of Ready.

1. You can run the following commands to ensure the pods for the data controller are deployed correctly:

```bash
kubectl get datacontroller --namespace <namespace of custom location>
```
When you run the following command:

```bash
kubectl get pods --namespace <namespace of custom location>
```
You should results like the following:

```md
NAME                            READY   STATUS      RESTARTS   AGE
arc-webhook-job-24ea7-dnq6x     0/1     Completed   0          19m
bootstrapper-547876c565-6zs8h   1/1     Running     0          19m
control-27cg2                   2/2     Running     0          18m
controldb-0                     2/2     Running     0          18m
logsdb-0                        3/3     Running     0          17m
logsui-9z9wb                    3/3     Running     0          15m
metricsdb-0                     2/2     Running     0          17m
metricsdc-fbz7k                 2/2     Running     0          17m
metricsdc-ghx7z                 2/2     Running     0          17m
metricsdc-ppzxg                 2/2     Running     0          17m
metricsui-pwnfk                 2/2     Running     0          17m
```
You are now ready to proceed to deploy an Azure Arc-enabled SQL Managed Instance.