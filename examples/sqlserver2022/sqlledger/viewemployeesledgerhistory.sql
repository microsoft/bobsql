USE ContosoHR;
GO
SELECT e.EmployeeID, e.FirstName, e.LastName, e.Salary, 
dlt.transaction_id, dlt.commit_time, dlt.principal_name, e.ledger_operation_type_desc, dlt.table_hashes
FROM sys.database_ledger_transactions dlt
JOIN dbo.Employees_Ledger e
ON e.ledger_transaction_id = dlt.transaction_id
ORDER BY dlt.commit_time DESC;
GO