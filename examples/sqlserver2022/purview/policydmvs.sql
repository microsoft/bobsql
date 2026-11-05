-- Lists generally supported actions
SELECT * FROM sys.dm_server_external_policy_actions;
GO
-- Lists the roles that are part of a policy published to this server
SELECT * FROM sys.dm_server_external_policy_roles;
GO
-- Lists the links between the roles and actions, could be used to join the two
SELECT * FROM sys.dm_server_external_policy_role_actions;
GO
