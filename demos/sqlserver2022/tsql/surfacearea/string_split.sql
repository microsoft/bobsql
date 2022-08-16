-- This is a demo for the enhanced STRING_SPLIT() T-SQL function in SQL Server 2022
-- Thanks to Aaron Bertrand for providing a base for these demos
DECLARE @states NVARCHAR(max) = N'Cowboys,Browns,Seahawks,Broncos,Eagles';
SELECT value as nfl_team FROM STRING_SPLIT(@states, N',');
GO
-- Notice this does not need a sort
DECLARE @states NVARCHAR(max) = N'Cowboys,Browns,Seahawks,Broncos,Eagles';
SELECT value as nfl_team, ordinal as rank FROM STRING_SPLIT(@states, N',', 1);
ORDER BY ordinal;
GO