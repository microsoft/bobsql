# SQL Server on Linux

In this example, you will learn how to use Polybase and SQL Server Machine Learning Services.

## Requirements

In order to use these examples you will need to install the following:

- An Oracle 18 instance. I used Oracle Express Edition which you can download at https://www.oracle.com/database/technologies/appdev/xe.html and installed it on Azure Virtual Machine.
- A SQL Server 2019 Linux deployment on a VM or server that can connect to the Oracle Instance. I installed SQL Server 2019 on Linux Ubuntu which you can read more at https://docs.microsoft.com/en-us/sql/linux/quickstart-install-connect-ubuntu?view=sql-server-ver15.
- Install and enable Polybase on your SQL Server Linux installation. You can read more how to do this at https://docs.microsoft.com/en-us/sql/relational-databases/polybase/polybase-linux-setup?view=sql-server-ver15.
- Install and enable SQL Server Machine Learning Service son your Linux installation. You can read more how to do this at https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup-machine-learning?view=sql-server-ver15.
- Install Azure Data Studio which can connect to the SQL Server on Linux VM or Server. You can learn how to install Azure Data Studio at https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio?view=sql-server-ver15.

## Steps

- Execute the PL/SQL script **createuser.sql** on your Oracle instance as the SYSTEM user.
- Execute the PL/SQL script **createtable.sql** on your Oracle instance using the user (orauser) created from createuser.sql.
- Execute the PL/SQL script **insertdata.sql** on your Oracle instance using the user (orauser).
- Create a database in the SQL Server Linux instance called **TutorialDB**. Use all the defaults.
- Open the **oracleexternaltable.ipynb** notebook in Azure Data Studio and connect to the SQL Server Linux instance. Execute each step in the notebook.
- Open the **rental_predictions.ipynb** notebook in Azure Data Studio and connect to the SQL Server Linux instance. Execute each step in the notebook.