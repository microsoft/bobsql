CREATE PROCEDURE [dbo].[getcustomer_byid]
  @customer_id int
AS
  SELECT * FROM customers WHERE customer_id = @customer_id;
RETURN 0
