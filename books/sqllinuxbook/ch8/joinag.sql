ALTER AVAILABILITY GROUP [footballag] JOIN WITH (CLUSTER_TYPE = EXTERNAL)
GO
-- Do not run this statement on the configuration replica
ALTER AVAILABILITY GROUP [footballag] GRANT CREATE ANY DATABASE
GO