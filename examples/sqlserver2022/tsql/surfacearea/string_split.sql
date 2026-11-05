-- This is a demo for the enhanced STRING_SPLIT() T-SQL function in SQL Server 2022
-- Thanks to Aaron Bertrand for providing a base for these demos
-- Step 1: Use STRING_SPLIT to get back a list of NFL teams. There is no guarantee for the order but it may work.
USE master;
GO
DECLARE @nflteams NVARCHAR(max) = N'Cowboys,Browns,Seahawks,Broncos,Eagles';
SELECT value as nfl_team FROM STRING_SPLIT(@nflteams, N',');
GO
-- Step 2: Use the new ordinal option to ensure order without a sort
USE master;
GO
DECLARE @nflteams NVARCHAR(max) = N'Cowboys,Browns,Seahawks,Broncos,Eagles';
SELECT value as nfl_team, ordinal as rank FROM STRING_SPLIT(@nflteams, N',', 1)
ORDER BY ordinal;
GO