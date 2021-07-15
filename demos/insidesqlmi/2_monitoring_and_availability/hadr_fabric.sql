select db_name(database_id), * from sys.dm_database_replica_states;
go
select * from sys.dm_hadr_fabric_nodes;
go
select replica_role_desc, * from sys.dm_hadr_fabric_deployed_replicas;
go