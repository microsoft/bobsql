USE master;
GO
DROP DATABASE IF EXISTS bwdb;
GO
CREATE DATABASE bwdb;
GO
USE [bwdb]
GO
PRINT 'Creating customers table...';
GO
CREATE TABLE [dbo].[customers]
(
  tabkey int, customer_id nvarchar(10), customer_information varchar(1000)
);
PRINT 'Creating customers index...';
GO
CREATE NONCLUSTERED INDEX [idx_customer_id]
ON [dbo].[customers] ([customer_id]);
GO
PRINT 'Creating stored procedure...';
GO
CREATE PROCEDURE [dbo].[getcustomer_byid]
  @customer_id nvarchar(10)
AS
  SELECT * FROM customers WHERE customer_id = @customer_id;
RETURN 0;
GO
PRINT 'Populating data...';
GO
truncate table customers;
with cte
as
(
select ROW_NUMBER() over(order by c1.object_id) id from sys.columns c1 cross join sys.columns c2
)
insert customers
select id, convert(nvarchar(10), id),'customer details' from cte;
GO