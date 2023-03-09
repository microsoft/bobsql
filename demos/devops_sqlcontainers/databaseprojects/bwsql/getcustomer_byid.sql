CREATE PROCEDURE [dbo].[getcustomer_byid]
  @customer_id nvarchar(10)
AS
  SELECT * FROM customers WHERE customer_id = @customer_id;
RETURN 0
