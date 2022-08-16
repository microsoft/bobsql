DBCC TRACEON(3604);
GO
-- Dump out the PFS page in master
-- Look at the BUF structure output
-- bstat should be 0xb
DBCC PAGE(1,1,3);
GO

/*
BUF_ONLRU = 0x000001
BUF_DIRTY = 0x000002
BUF_IO      0x000004
BUF_HASHED  0x000008
*/
-- Search for the bstat value for this page
DECLARE @bstat varbinary(4);
SET @bstat = 0xb
SELECT BIT_COUNT(@bstat);
SELECT GET_BIT(@bstat, 3) as "2^3", GET_BIT(@bstat, 2) as "2^2", GET_BIT(@bstat, 1) as "2^1", GET_BIT(@bstat, 0) as "2^0";
SELECT GET_BIT(@bstat, 3)*2*2*2+GET_BIT(@bstat, 2)*2*2+GET_BIT(@bstat, 1)*2+GET_BIT(@bstat, 0)*1;
SELECT cast((GET_BIT(@bstat, 3)*2*2*2+GET_BIT(@bstat, 2)*2*2+GET_BIT(@bstat, 1)*2+GET_BIT(@bstat, 0)*1) as varbinary(4));
GO