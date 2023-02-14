USE MASTER;
GO
DROP DATABASE IF EXISTS query_antipattern;
GO
CREATE DATABASE query_antipattern;
GO
USE query_antipattern;
GO
-- Create a table
--
DROP TABLE IF EXISTS customers;
GO
CREATE TABLE customers (tabkey int, customer_id nvarchar(10), customer_information varchar(1000));
GO
-- Populate 1 million rows of data into the table
--
with cte
as
(
select ROW_NUMBER() over(order by c1.object_id) id from sys.columns c1 cross join sys.columns c2
)
insert customers
select id, convert(nvarchar(10), id),'customer details' from cte
go
select count(*) FROM customers
go
-- Create indexes for both customer_tabkey and customer_id
CREATE NONCLUSTERED INDEX [idx_customer_tabkey]
ON [dbo].[customers] ([tabkey])
GO
CREATE NONCLUSTERED INDEX [idx_customer_id]
ON [dbo].[customers] ([customer_id])
GO
-- Create a stored procedure to select a row
--
CREATE or ALTER PROC getcustomer @tabkey int
AS
SELECT * FROM customers WHERE tabkey = @tabkey;
GO
-- Create another procedure to select a row by customer_id
--
CREATE or ALTER PROC getcustomer_byid @customer_id int
AS
SELECT * FROM customers WHERE customer_id = @customer_id;
GO



