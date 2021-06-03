-- Dump out the first PFS page for master
-- checkpoint master in case there is any residual changes
use master
go
checkpoint
go
dbcc traceon(3604)
go
dbcc page(1,1,1,3)
go
-- bstat shows 0x9. Show this in binary in calculator which is 1001
-- This translates to BUF_ONLRU (2 to the 0 power is 1) + BUF_HASHED (2 to the 4 power is 8) = 9
--
-- Create a table in master and insert a row
use master
go
drop table mytab
go
create table mytab (col1 int)
go
insert into mytab values (1)
go
--
-- Dump out the PFS page for master again
dbcc traceon(3604)
go
dbcc page(1,1,1,3)
go
-- bstat is now 0xb which is 1011. The new bit is BUF_DIRTY (2 to the 1st power is 2)
-- 0x9 + 0x2 = 0xb
--
-- Now Checkpoint master
--
checkpoint
-- Does the bstat change?
--
dbcc traceon(3604)
go
dbcc page(1,1,1,3)
go
-- bstat is now 0x9. The BUF_DIRTY bit is cleared
