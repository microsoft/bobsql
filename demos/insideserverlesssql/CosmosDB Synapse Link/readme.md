# Demo for using Serverless SQL Pool with Azure Synapse Link for Cosmos DB

This demo will show you the basics of how to use Serverless SQL Pools with Cosmos DB Synapse Link. This demo uses an example from the Synapse samples GitHub [repo](https://github.com/Azure-Samples/Synapse).

1. Clone this GitHub repo: https://github.com/Azure-Samples/Synapse

2. Follow the Prerequisites at https://github.com/Azure-Samples/Synapse/tree/main/Notebooks/PySpark/Synapse%20Link%20for%20Cosmos%20DB%20samples

3. Enable Synpase link for your CosmosDB account per this [documentation](https://docs.microsoft.com/azure/cosmos-db/configure-synapse-link#enable-synapse-link).

4. Connect your Synapse workspace to CosmosDB per this [documentation](https://docs.microsoft.com/azure/synapse-analytics/synapse-link/how-to-connect-synapse-link-cosmos-db)

5. Use Azure Synapse Studio to execute this notebook to ingest data: https://github.com/Azure-Samples/Synapse/blob/main/Notebooks/PySpark/Synapse%20Link%20for%20Cosmos%20DB%20samples/IoT/spark-notebooks/pyspark/01-CosmosDBSynapseStreamIngestion.ipynb. This [documentation](https://docs.microsoft.com/azure/synapse-analytics/spark/apache-spark-development-using-notebooks?tabs=classical) gives you guidance on how to run notebooks in Synapse Studio. In this notebook be sure to update the linkedService name to the one you created in Step 4 if different from default name of CosmosDBIoTDemo. The last cell should run for about 5 minutes before you stop the streaming.

6. Then execute this notebook: https://github.com/Azure-Samples/Synapse/blob/main/Notebooks/PySpark/Synapse%20Link%20for%20Cosmos%20DB%20samples/IoT/spark-notebooks/pyspark/02-CosmosDBSynapseBatchIngestion.ipynb to ingest data for IoTDeviceInfo.

7. Now execute the following T-SQL script from Synapse Studio or any T-SQL based tool connected to the Serverless SQL Pool front-end server

```sql
SELECT TOP 100 *
FROM OPENROWSET( 
       'CosmosDB',
       'Account=<cosmosdb account>;Database=<CosmosDBIoTDemo>;Key=<cosmosdb key>',
       IoTSignals) as IoTSignals
```

8. Go back and run the notebook cell to ingest data for signals and re-run the Serverless SQL script. HTAP at work!