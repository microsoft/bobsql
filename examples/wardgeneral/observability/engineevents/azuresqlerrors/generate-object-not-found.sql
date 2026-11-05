/*
    Ward General — Observability
    Generate one object-not-found error for the AzureSQLErrors demonstration.

    The misspelled Ward General table name raises system error 208, severity 16.
    This changes no data or schema. A nonzero client exit is expected.
*/

SET NOCOUNT ON;

SELECT TOP (1) *
FROM clinical.Observaton;