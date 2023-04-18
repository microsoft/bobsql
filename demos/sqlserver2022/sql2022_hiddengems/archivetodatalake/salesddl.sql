USE master;
GO
DROP DATABASE IF EXISTS SalesDB;
GO
CREATE DATABASE SalesDB;
GO
USE SalesDB;
GO
DROP TABLE IF EXISTS Sales;
GO
DROP PARTITION SCHEME myRangePS;
GO
DROP PARTITION FUNCTION myRangePF;
GO
CREATE PARTITION FUNCTION myRangePF (date)  
    AS RANGE RIGHT FOR VALUES ('20221001', '20221101', '20221201') ;  
GO

CREATE PARTITION SCHEME myRangePS  
    AS PARTITION myRangePF  
    ALL TO ('PRIMARY') ;  
GO
CREATE TABLE Sales (salesid int identity not null, customer varchar(50) not null, sales_dt date not null, salesperson varchar(50) not null, sales_amount bigint not null,
CONSTRAINT PKSales PRIMARY KEY CLUSTERED(sales_dt, salesid))
ON myRangePS (sales_dt);
GO

-- Insert data for the 5 partitions
--
-- Insert data for September 2022
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 1', '20220901', 'SalesPerson1', 100);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 2', '20220902', 'SalesPerson1', 200);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 3', '20220903', 'SalesPerson1', 300);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 4', '20220904', 'SalesPerson2', 400);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 5', '20220905', 'SalesPerson2', 500);

--
-- Insert data for October 2022
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 1', '20221001', 'SalesPerson1', 100);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 2', '20221002', 'SalesPerson1', 200);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 3', '20221003', 'SalesPerson1', 300);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 4', '20221004', 'SalesPerson2', 400);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 5', '20221005', 'SalesPerson2', 500);
--
-- Insert data for November 2022
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 1', '20221101', 'SalesPerson1', 100);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 2', '20221102', 'SalesPerson1', 200);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 3', '20221103', 'SalesPerson1', 300);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 4', '20221104', 'SalesPerson2', 400);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 5', '20221105', 'SalesPerson2', 500);

--
-- Insert data for December 2022
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 1', '20221201', 'SalesPerson1', 100);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 2', '20221202', 'SalesPerson1', 200);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 3', '20221203', 'SalesPerson1', 300);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 4', '20221204', 'SalesPerson2', 400);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 5', '20221205', 'SalesPerson2', 500);

--
-- Insert data for January 2023
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 1', '20230101', 'SalesPerson1', 100);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 2', '20230102', 'SalesPerson1', 200);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 3', '20230103', 'SalesPerson1', 300);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 4', '20230104', 'SalesPerson2', 400);
INSERT INTO Sales (customer, sales_dt, salesperson, sales_amount)
VALUES ('Customer 5', '20230105', 'SalesPerson2', 500);

-- Check partitions
--
SELECT 
    p.partition_number AS [Partition], 
    fg.name AS [Filegroup], 
    p.Rows
FROM sys.partitions p
    INNER JOIN sys.allocation_units au
    ON au.container_id = p.hobt_id
    INNER JOIN sys.filegroups fg
    ON fg.data_space_id = au.data_space_id
WHERE p.object_id = OBJECT_ID('Sales');
GO

-- Create an archive table that is empty
--
DROP TABLE IF EXISTS SalesArchive;
GO
CREATE TABLE SalesArchive (salesid int identity not null, customer varchar(50) not null, sales_dt date not null, salesperson varchar(50) not null, sales_amount bigint not null,
CONSTRAINT PKSalesArchive PRIMARY KEY CLUSTERED(sales_dt, salesid));
GO






