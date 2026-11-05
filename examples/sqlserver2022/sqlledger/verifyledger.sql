USE ContosoHR;
GO
EXECUTE sp_verify_database_ledger 
N'<saved digest JSON>'
GO