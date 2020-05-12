# SQL Server Containers

In this example, you will learn how to use SQL Server Containers for a DevOps pipeline.

## Requirements

In order to use these examples you will need:

- A Github repository to host your code
- An Azure DevOps account

## Steps

- Copy all the files in the **wwi** directory into your GitHub repository.
- Login to your Azure DevOps account (dev.azure.com). Using Azure DevOps create a new project called **wwi**.
- Using your Azure DevOps project create a new pipeline called **wwi**. Provide the GitHub repository URL for where you source code exists.
- To see an automated job, change the image for SQL Server to **2019-CU4-ubuntu-18.04** in **docker-compose.yml**. Save the change. Commit and push your change to your main branch of your repository.
- View the Job output in Azure DevOps pipeline.