# Using Azure OpenAI for vector search in SQL Server 2025

This is a demo to show AI capabilities for SQL Server 2025 using Azure OpenAI. This includes AI model definition, vector data type, embedding generation, vector index, and vector search.

## Pre-requisites

Here are the minimum requirements to run the demos:

1. This demo uses an AI model from Azure OpenAI. You will need to have an Azure subscription to use this model. The model used in this demo is **text-embedding-ada-002**.
    1. Use the Azure Portal to create an **Azure AI Foundry project**. Learn more at <https://learn.microsoft.com/azure/ai-studio/how-to/create-project>.
    1. Deploy the text-embedding-ada-002 model from the model catalog in your project. Learn more at <https://learn.microsoft.com/azure/ai-studio/how-to/deploy-models-openai>. You will need the AI service endpoint and API key to use the model. You can get this from the Azure Portal for your project in Azure Ai Foundry..

1. Review the minimum requirements to run the demos in the [SQL Server 2025 AI Demos](../readme.md) readme.

5. Enable REST API support for the system procedure sp_invoke_external_rest_endpoint by executing the script **enablerestapi.sql**. This will enable the REST API support for the system procedure sp_invoke_external_rest_endpoint using sp_configure.

6. Enable vector index support in CTP builds by execute the script **enablevectorindex.sql**. This will enable the vector index support in SQL Server 2025 CTP builds using trace flags.

2. All demos will use the same database to show the differences with AI model capabilities Therefore, you will need to download the sample database AdventureWorks from <https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak>.

4. Restore the database using the script **restore_adventureworks.sql** (You may need to edit the file paths for the backup and/or database and log files). You can also use the **AdventureWorks.bacpac** file to import data and schema.

6. Load the script **creds.sql** in a SSMS query editor window. This script is used to create a database scoped credential to be used to communicate with the Azure AI model using an API key. Using the Azure AI Foundry user interface in the Azure Portal, select the text-embedding-ada-002 model and copy the API key from the Endpoint definition. You will need to make a few edits.

    1. Replace the **\<pwd\>** in the script with a strong password inside the quotes.
    1. Replace the **\<apikey\>** in the script with the API key from your Azure AI model deployment inside the quotes
    1. Replace the **\<azureai\>** in the script with the hostname portion of your endpoint. For example, if your endpoint is https://productsopenai.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15 the hostname would be https://productsopenai.openai.azure.com inside the quotes or brackets.

7. Define the AI model to use by loading and executing the script **create_external_model.sql**. This script will create a model called **text-embedding-ada-002** in the database. Replace the **\<azureai\>** in the script with the hostname portion of your endpoint.

## References

Find out more about SQL Server 2025 at https://aka.ms/sqlserver2025docs.

## Demo - Execute a vector search with Azure OpenAI

This demo shows how to execute a vector search using an Azure OpenAI model. In this demo you learn to generate embeddings from text data in the database and store them in a vector data type column. You will also build a vector index based on this column.

Then you will use a stored procedure to execute a vector search based on natural language prompt against the vector index.

1. Load and execute the script **embedding_table.sql**. This script will create a table called **ProductDescriptionEmbeddings** with a vector column called **Embedding**. Embeddings are generated based on the **Description** column in the **ProductDescription** table using the **AI_GENERATE_EMBEDDINGS** function. This table will have keys to be able to join with other tables in the database to help with vector searching.

This script also creates a unique non-clustered index to support a vector index creation in the next step.

2. Load and execute the script **create_vector_index.sql**. This script will create a vector index on the **Embedding** column of the **ProductDescriptionEmbeddings** table. This index will be used to optimize vector searches against the embeddings stored in this table.

3. Load and execute the script **find_relevant_products_vector_search.sql**. This script will create a stored procedure called **find_relevant_products_vector_search** that will execute a vector search against the **ProductDescriptionEmbeddings** table using the vector index created in the previous step. The stored procedure will take a natural language prompt as input, generate embeddings with AI_GENERATE_EMBEDDINGS() from the prompt, and return the top 10 most relevant products based on the vector search.

4. You can now perform a vector search using the stored procedure. Load the script **find_relevant_products_vector_search.sql**. In this script you can provide a natural language prompt with words and phrases that are not exactly in product descriptions. Vector search allows you to find similar results based on embeddings. Notice in the script examples are provided for mulitple languages and the results match the language of the prompt without changing any code because the embedding model used from Azure OpenAI is optimized for multiple languages. You can also use the **TOP** clause to limit the number of results returned. The default is 10. You can change this to any number you want.