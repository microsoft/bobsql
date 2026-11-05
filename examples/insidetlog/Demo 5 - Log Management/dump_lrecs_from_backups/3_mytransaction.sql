USE findmytransaction;
GO
BEGIN TRAN mytransaction WITH MARK;
GO
INSERT INTO atablewithdata VALUES (1);
INSERT INTO atablewithdata VALUES (2);
GO

-- Run this delete after the 1st log backup
--
DELETE FROM atablewithdata;
COMMIT TRAN mytransaction;
GO





