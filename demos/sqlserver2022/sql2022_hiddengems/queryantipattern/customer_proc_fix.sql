USE query_antipattern;
GO
CREATE or ALTER PROC getcustomer_byid @customer_id nvarchar(10)
AS
SELECT * FROM customers WHERE customer_id = @customer_id;
GO

