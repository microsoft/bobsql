-- Create MonitoringProcs.sql
-- Connect to sqlscale.database.windows.net - DemoDBGP ( or a GP database)

-- Resource Stats
select * from sys.dm_db_resource_stats

-- DB limits 
select  database_name,slo_name,cpu_limit,max_db_memory
,max_db_max_size_in_mb, primary_max_log_rate,primary_group_max_io, volume_local_iops,volume_pfs_iops
from  sys.dm_user_db_resource_governance

select *
from sys.dm_resource_governor_resource_pools_history_ex 
where name like '%UserPool%'

select * from sys.dm_resource_governor_resource_pools 
select * from sys.dm_resource_governor_workload_groups

select * from sys.dm_resource_governor_workload_groups_history_ex
where name like 'User%'


select snapshot_time, name, max_log_rate_kb, delta_log_bytes_used from sys.dm_resource_governor_resource_pools_history_ex where name like 'UserPool%' order by snapshot_time desc

select * from sys.dm_os_memory_clerks
where  type like '%MEMORYCLERK_RBPEX%'




-- Create a table and Schema
IF SCHEMA_ID('DataLoad') IS NULL 
EXEC ('CREATE SCHEMA DataLoad')

DROP TABLE IF EXISTS DataLoad.store_returns
go
CREATE TABLE DataLoad.store_returns
(
    sr_returned_date_sk             bigint,
    sr_return_time_sk               bigint,
    sr_item_sk                      bigint           ,
    sr_customer_sk                  bigint,
    sr_cdemo_sk                     bigint,
    sr_hdemo_sk                     bigint,
    sr_addr_sk                      bigint,
    sr_store_sk                     bigint,
    sr_reason_sk                    bigint,
    sr_ticket_number                bigint           ,
    sr_return_quantity              integer,
    sr_return_amt                   float,
    sr_return_tax                   float,
    sr_return_amt_inc_tax           float,
    sr_fee                          float,
    sr_return_ship_cost             float,
    sr_refunded_cash                float,
    sr_reversed_charge              float,
    sr_store_credit                 float,
    sr_net_loss                     float

) 
GO

-- Create a master key
IF not exists ( select 1 from sys.symmetric_keys where name = '##MS_DatabaseMasterKey##')
CREATE MASTER KEY 
ENCRYPTION BY PASSWORD='MyComplexPassword00!';
GO 

/*
drop EXTERNAL DATA SOURCE tpcds
drop database scoped credential [https://denzilrdiag.blob.core.windows.net/adata/] 
*/

-- Create a credential to blob storage account that has files with SAS token.

IF NOT EXISTS ( select 1 from sys.database_credentials
where name = 'https://denzilrdiag.blob.core.windows.net/adata/')
CREATE DATABASE SCOPED CREDENTIAL [https://denzilrdiag.blob.core.windows.net/adata/]
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'sv=2019-02-02&st=2020-08-04T20%3A44%3A34Z&se=2021-08-05T20%3A44%3A00Z&sr=c&sp=rl&sig=OnCMhPg9ggKdDfwatuiGIaiVDYVG54n2ws%2FDw%2BD0C%2Fk%3D';
GO


-- Create an external data source to the container
-- Note LOCATIOn doesn't have trailing /
IF NOT EXISTS ( select 1 from sys.external_data_sources 
where name = 'tpcds')
CREATE EXTERNAL DATA SOURCE tpcds
WITH 
(
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://denzilrdiag.blob.core.windows.net/adata',
    CREDENTIAL = [https://denzilrdiag.blob.core.windows.net/adata/]
);

-- BULK insert a single file
-- View Log generation rate during this time
-- This single file takes 0:29 secons on GP 8core -- doesn't push limits
SET NOCOUNT ON
GO
 BULK INSERT DataLoad.store_returns
 FROM 'tpcds/store_returns/store_returns_1.dat'
     WITH (
			DATA_SOURCE = 'tpcds'
			,DATAFILETYPE = 'char'
	        ,FIELDTERMINATOR = '\|'
	        ,ROWTERMINATOR = '\|\n'
            --,BATCHSIZE=100000
            , TABLOCK
           )
GO

-- select 
select count(*) from DataLoad.store_returns
--- Now run the Powershell Script DataLoadGP.ps1 with 4 threads


-- Show requests
-- IMPPROV_IOWAIT is due to bulk insert having to read the file
-- LOG_RATE_GOVERNOR shows log is throttled. it may be there for a bit
exec getRequests


-- Get Waitstats delta 
--- Have to execute 2 times 
exec getWaitstatsDelta



-- Resource Stats?
select * from sys.dm_db_resource_stats
order by end_time desc






DROP TABLE IF EXISTS DataLoad.store_returnsCCI
go
CREATE TABLE DataLoad.store_returnsCCI
(
    sr_returned_date_sk             bigint,
    sr_return_time_sk               bigint,
    sr_item_sk                      bigint           ,
    sr_customer_sk                  bigint,
    sr_cdemo_sk                     bigint,
    sr_hdemo_sk                     bigint,
    sr_addr_sk                      bigint,
    sr_store_sk                     bigint,
    sr_reason_sk                    bigint,
    sr_ticket_number                bigint           ,
    sr_return_quantity              integer,
    sr_return_amt                   float,
    sr_return_tax                   float,
    sr_return_amt_inc_tax           float,
    sr_fee                          float,
    sr_return_ship_cost             float,
    sr_refunded_cash                float,
    sr_reversed_charge              float,
    sr_store_credit                 float,
    sr_net_loss                     float

) 
GO

