-- Add a target group containing server(s)
EXEC jobs.sp_add_target_group 'bwazuresqlgroup'

-- Add a server target member
EXEC jobs.sp_add_target_group_member
'bwazuresqlgroup',
@target_type = 'SqlServer',
@refresh_credential_name='mymastercred', --credential required to refresh the databases in a server
@server_name='bwazuresqlserver.database.windows.net';
GO

-- Add a server target member
EXEC jobs.sp_add_target_group_member
'bwazuresqlgroup',
@membership_type = 'Exclude',
@target_type = 'SqlDatabase',
@server_name='bwazuresqlserver.database.windows.net',
@database_name = 'bwazuresqldbhyper';
GO

EXEC jobs.sp_add_target_group_member
'bwazuresqlgroup',
@membership_type = 'Exclude',
@target_type = 'SqlDatabase',
@server_name='bwazuresqlserver.database.windows.net',
@database_name = 'bwazuresqldbserverless';
GO

--View the recently created target group and target group members
SELECT * FROM jobs.target_groups WHERE target_group_name='bwazuresqlgroup';
SELECT * FROM jobs.target_group_members WHERE target_group_name='bwazuresqlgroup';
GO