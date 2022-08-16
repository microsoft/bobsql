-- This is a demo for the enhanced STRING_SPLIT() T-SQL function in SQL Server 2022
DECLARE @states NVARCHAR(max) = N'Cowboys,Browns,Seahawks,Broncos,Eagles';
SELECT value as nfl_team FROM STRING_SPLIT(@states, N',')
GO
DECLARE @states NVARCHAR(max) = N'Cowboys,Browns,Seahawks,Broncos,Eagles';
SELECT value as nfl_team, ordinal as rank FROM STRING_SPLIT(@states, N',', 1)
ORDER BY ordinal;
GO