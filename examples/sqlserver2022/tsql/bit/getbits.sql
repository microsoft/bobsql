-- Step 1: Run DBCC page against the PFS page and look at a member of the BUF structure
-- Dump out the PFS page in master
-- Look at the BUF structure output
-- bstat should be 0x9
-- It could be 0xb if someone has made any page allocations and master has not been checkpointed. For a new installed SQL Server it should be 0x9
-- If you see 0x109 it could because of an internal bit for checkpointing but it can be ignored
-- Here are several bstat values packed into this number
/*
BUF_ONLRU = 0x000001
BUF_DIRTY = 0x000002
BUF_IO      0x000004
BUF_HASHED  0x000008
*/
USE master;
GO
-- Checkpoint master to clear any dirty bits for PFS
CHECKPOINT;
GO
DBCC TRACEON(3604);
GO
DBCC PAGE(1,1,1,3);
GO
-- Step 2: Get a count of bits that are 1 in the value
USE master;
GO
DECLARE @bstat varbinary(4);
SET @bstat = 0x9;
SELECT BIT_COUNT(@bstat);
GO
-- Step 3: Which bits are on in the packed value
USE master;
GO
DECLARE @bstat varbinary(4);
SET @bstat = 0x9;
SELECT GET_BIT(@bstat, 3) as "2^3 BUF_HASHED", GET_BIT(@bstat, 2) as "2^2 BUF_IO", GET_BIT(@bstat, 1) as "2^1 BUF_DIRTY", GET_BIT(@bstat, 0) as "2^0 BUF_ONLRU";
GO
-- Step 4: Combine the packed bits back into the number
USE master;
GO
DECLARE @bstat varbinary(4);
SET @bstat = 0x9;
SELECT GET_BIT(@bstat, 3)*2*2*2+GET_BIT(@bstat, 2)*2*2+GET_BIT(@bstat, 1)*2+GET_BIT(@bstat, 0)*1;
SELECT cast((GET_BIT(@bstat, 3)*2*2*2+GET_BIT(@bstat, 2)*2*2+GET_BIT(@bstat, 1)*2+GET_BIT(@bstat, 0)*1) as varbinary(4));
GO
-- Step 5: Create a table in master and see if there are changes
USE master;
GO
DROP TABLE IF EXISTS cowboysrule;
GO
CREATE TABLE cowboysrule (col1 int);
INSERT INTO cowboysrule VALUES (1);
GO
-- bstat should now be 0xb
DBCC TRACEON(3604);
GO
DBCC PAGE(1,1,1,3);
GO
-- BUF_DIRTY is now ON which means the page has been modified but not written.
-- The PFS page is modified because a page allocation was required for the new table data
DECLARE @bstat varbinary(4);
SET @bstat = 0xb;
SELECT GET_BIT(@bstat, 3) as "2^3 BUF_HASHED", GET_BIT(@bstat, 2) as "2^2 BUF_IO", GET_BIT(@bstat, 1) as "2^1 BUF_DIRTY", GET_BIT(@bstat, 0) as "2^0 BUF_ONLRU";
GO
-- Step 6: Cleanup the table we created in master and checkpoint it to clear the dirty bit
USE master;
GO
DROP TABLE IF EXISTS cowboysrule;
GO
CHECKPOINT;
GO