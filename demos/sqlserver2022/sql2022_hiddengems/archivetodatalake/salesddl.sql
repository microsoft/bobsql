USE SalesDB;
GO
DROP TABLE IF EXISTS Sales;
GO
DROP PARTITION FUNCTION IF EXISTS myRangePF;
GO
CREATE PARTITION FUNCTION myRangePF (datetime2)  
    AS RANGE RIGHT FOR VALUES ('2022-10-01', '2023-11-01', '2022-12-01') ;  
GO
DROP PARTITION SCHEME myR
CREATE PARTITION SCHEME myRangePS  
    AS PARTITION myRangePF  
    ALL TO ('PRIMARY') ;  
GO
CREATE TABLE Sales (salesid int primary key clustered identity, customer varchar(50), sales_dt datetime2, salesperson varchar(50), sales_amount bigint)
ON myRangePS (sales_dt);
GO





