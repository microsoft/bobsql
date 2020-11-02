--Add job for create table
EXEC jobs.sp_add_job @job_name='ReorganizeIndexes', @description='Reorganize Indexes';
GO

-- Add job step for create table
EXEC jobs.sp_add_jobstep @job_name='ReorganizeIndexes',
@command=N'ALTER INDEX PK_SalesOrderDetail_SalesOrderID_SalesOrderDetailID
ON SalesLT.SalesOrderDetail REORGANIZE;',
@credential_name='myjobcred',
@target_group_name='bwazuresqlgroup';
GO