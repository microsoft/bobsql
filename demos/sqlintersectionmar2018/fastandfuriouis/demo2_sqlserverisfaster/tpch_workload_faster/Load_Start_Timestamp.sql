--	Create temporary table for timing in the Master Database
--
--              This is just temporary until we build the TPCH_AUX_TABLE later
--

--
--  Delete any existing tpch_temp_timer table
--
if exists ( select name from sysobjects where name = 'tpch_temp_timer' )
	drop table tpch_temp_timer

--
--  Create the temporary table
--
create table tpch_temp_timer
(
	load_start_time				datetime
)

--
--  Store the starting time in the temporary table
--
insert	into tpch_temp_timer values (getdate())

