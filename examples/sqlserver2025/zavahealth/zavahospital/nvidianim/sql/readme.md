# Connect SQL Server to NIM

Numbered SQL scripts for testing the endpoints provisioned by the
[NIM deployment guide](../README.md):

1. Review [00_setup.sql](00_setup.sql) for database configuration.
2. Inspect [01_create_external_model.sql](01_create_external_model.sql).
3. Use [02_test_embedding.sql](02_test_embedding.sql) to verify embeddings.
4. Review [03_enable_rest_endpoint.sql](03_enable_rest_endpoint.sql) before
   changing endpoint settings.
5. Use [04_test_chat_completion.sql](04_test_chat_completion.sql) to verify chat.

SQL Server 2025 must trust and resolve the configured TLS endpoint. Confirm
model names and embedding dimensions match deployment. These tests make model
calls; use synthetic inputs and privately supplied configuration. Do not treat
a successful connectivity test as validation of the whole hospital scenario.
