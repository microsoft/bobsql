-- Enable Resource Governor if not already enabled
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO

-- Create a new Workload Group with only GROUP_MAX_TEMPDB_DATA_MB option
CREATE WORKLOAD GROUP ReportUsers
WITH (GROUP_MAX_TEMPDB_DATA_MB = 100);
GO

-- Apply the changes
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO